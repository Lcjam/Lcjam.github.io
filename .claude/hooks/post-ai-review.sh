#!/usr/bin/env bash
#
# PreToolUse(Bash) hook — `git commit` 직전에 스테이징된 블로그 글이
# "AI가 쓴 티"가 나는지 최종 검토한다.
#
#   1단계 린터(고정밀, 무료/즉시): 작가의 실제 평어체 목소리엔 없는데
#          AI가 흘리기 쉬운 신호만 잡는다 — 어조 혼용 / 영어 잔재 / 상투구.
#   2단계 LLM 게이트(claude -p): 1단계를 통과하면 기존 문체 기준으로
#          사람이 직접 쓴 글처럼 읽히는지 최종 판정한다.
#
# 문제가 있으면 exit 2로 커밋을 막고, 이유를 stderr로 돌려준다(→ Claude가
# 그 피드백을 보고 글을 고친 뒤 다시 커밋).
#
# 빠져나가기: 환경변수 SKIP_AI_REVIEW=1 이면 검토를 건너뛴다.
# LLM 판정 모델은 아래 MODEL 변수로 조절.

set -uo pipefail

MODEL="claude-sonnet-4-6"   # 2단계 판정 모델 (속도/비용 vs 정밀도 조절)

input=$(cat)

# --- git commit 호출에만 반응 ---------------------------------------------
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

[ "${SKIP_AI_REVIEW:-0}" = "1" ] && exit 0
command -v git >/dev/null 2>&1 || exit 0

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo_root" || exit 0

# --- 스테이징된 글(_posts/*.md)만 추린다 (bash 3.2 호환) -------------------
posts=()
while IFS= read -r line; do
  [ -n "$line" ] && posts+=("$line")
done < <(git diff --cached --name-only --diff-filter=ACM -- '_posts/*.md' 2>/dev/null)
[ "${#posts[@]}" -eq 0 ] && exit 0

# 본문만 남긴다: 프런트매터(첫 두 ---) 제거 + 코드펜스(```) 제거 + 인라인코드(`...`) 제거
extract_body() {
  awk '
    BEGIN { fm = 0; code = 0 }
    /^---[[:space:]]*$/ { if (fm < 2) { fm++; next } }
    fm < 2 { next }
    /^[[:space:]]*```/ { code = !code; next }
    code { next }
    { print }
  ' | sed 's/`[^`]*`//g'
}

# 패턴 등장 횟수
count() { grep -oE "$1" 2>/dev/null | wc -l | tr -d ' '; }

problems=""
add_problem() { problems+="  - $1"$'\n'; }

# ==========================================================================
# 1단계: 결정론적 린터
# ==========================================================================
for f in "${posts[@]}"; do
  body=$(git show ":$f" 2>/dev/null | extract_body)
  [ -z "$body" ] && continue

  # (A) 어조 혼용 — 평어체 글에 존댓말이 섞였는가
  formal=$(printf '%s' "$body" | count '(습니다|합니다|입니다|됩니다|니다[.!? ])')
  formal=$((formal + $(printf '%s' "$body" | count '(세요|어요|에요|예요|아요|네요|까요|드려요|십시오)[.!? ]')))
  plain_da=$(printf '%s' "$body" | count '다[.!?]')
  nida=$(printf '%s' "$body" | count '니다[.!?]')
  plain=$((plain_da - nida))
  [ "$plain" -lt 0 ] && plain=0
  if [ "$formal" -ge 2 ] && [ "$plain" -ge 2 ]; then
    add_problem "[$f] 평어체와 존댓말이 섞여 있다 (평어체 ~${plain} / 존댓말 ~${formal}). 한 어조로 통일."
  fi

  # (B) 영어 잔재 상투구 (AI 번역투)
  eng=$(printf '%s' "$body" | grep -oiE "\b(let me|here's|here is how|in conclusion|to summarize|overall,|note that|importantly,|furthermore|moreover|additionally,)\b" 2>/dev/null | head -3)
  if [ -n "$eng" ]; then
    add_problem "[$f] 영어 AI 상투구: $(printf '%s' "$eng" | paste -sd',' -)"
  fi

  # (C) 한국어 강한 상투구
  kor=$(printf '%s' "$body" | grep -oE "(결론적으로|요약하자면|정리하자면|살펴보겠습니다|알아보겠습니다)" 2>/dev/null | head -3)
  if [ -n "$kor" ]; then
    add_problem "[$f] 한국어 AI 상투구: $(printf '%s' "$kor" | paste -sd',' -)"
  fi
done

if [ -n "$problems" ]; then
  {
    echo "✋ 커밋 보류 — 1단계 린터가 AI 티로 의심되는 부분을 찾았다:"
    printf '%s' "$problems"
    echo "고친 뒤 다시 커밋하거나, 의도된 표현이면 SKIP_AI_REVIEW=1 로 우회."
  } >&2
  exit 2
fi

# ==========================================================================
# 2단계: LLM 게이트 (claude -p) — 린터 통과분만 최종 판정
# ==========================================================================
command -v claude >/dev/null 2>&1 || exit 0   # claude 없으면 1단계까지만 (fail-open)

rubric='너는 한국어 개발 블로그의 문체 검수자다. 아래 글이 "사람이 직접 쓴 글"로 읽히는지,
아니면 AI가 쓴 티가 나는지 판정해라. 이 블로그의 확립된 문체 기준:
- 평어체 반말("~다/~거다/~싶다"), 1인칭("나"), 직접 겪은 계기에서 출발하는 담담한 서술.
- 구체 숫자·표·코드로 보여주고, 군더더기 없이 짧게 끊는 문장. 약간의 구어("근데","뭐가 문제냐면") 허용.
- 장제부호(—), 굵게 강조, Chirpy 프롬프트 박스는 이 블로그의 정상 문체이니 AI 티로 보지 마라.
AI 티의 예: 기계적으로 균형 잡힌 3항 나열, 과한 헤징, 공허한 일반론, 매 문단 같은 길이,
존댓말 혼입, 번역투, "중요한 것은 ~라는 점이다"식 상투 마무리.
첫 줄에 반드시 "VERDICT: PASS" 또는 "VERDICT: REVISE" 만 출력하고,
REVISE면 다음 줄부터 고칠 부분을 짧은 불릿으로 적어라.'

llm_problems=""
for f in "${posts[@]}"; do
  body=$(git show ":$f" 2>/dev/null)
  [ -z "$body" ] && continue
  verdict=$(printf '%s\n\n=== 글: %s ===\n%s\n' "$rubric" "$f" "$body" \
            | claude -p --model "$MODEL" 2>/dev/null)
  [ -z "$verdict" ] && continue   # 호출 실패 시 해당 글은 통과(fail-open)
  if printf '%s' "$verdict" | head -1 | grep -qi 'REVISE'; then
    reasons=$(printf '%s' "$verdict" | tail -n +2)
    llm_problems+="[$f]"$'\n'"$reasons"$'\n\n'
  fi
done

if [ -n "$llm_problems" ]; then
  {
    echo "✋ 커밋 보류 — LLM 검토가 AI 티를 지적했다:"
    echo
    printf '%s' "$llm_problems"
    echo "고친 뒤 다시 커밋하거나, 의도된 표현이면 SKIP_AI_REVIEW=1 로 우회."
  } >&2
  exit 2
fi

exit 0
