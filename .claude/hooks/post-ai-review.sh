#!/usr/bin/env bash
#
# PreToolUse(Bash) hook — `git commit` 직전에 스테이징된 블로그 글이
# "AI가 쓴 티"가 나는지 최종 검토한다.
#
#   1단계 린터(고정밀, 무료/즉시): 작가의 실제 평어체 목소리엔 없는데
#          AI가 흘리기 쉬운 신호만 잡는다 — 어조 혼용 / 영어 잔재 / 상투구.
#   2단계 LLM 게이트(claude -p): 1단계를 통과하면 humanizer-ko 스킬
#          (~/.claude/skills/humanizer-ko/SKILL.md) 기준으로 최종 판정한다.
#
# 문제가 있으면 exit 2로 커밋을 막고, 이유를 stderr로 돌려준다(→ Claude가
# 그 피드백을 보고 글을 고친 뒤 다시 커밋).
#
# 빠져나가기: 환경변수 SKIP_AI_REVIEW=1 이면 검토를 건너뛴다.
# LLM 판정 모델은 아래 MODEL 변수로 조절.

set -uo pipefail

MODEL="claude-sonnet-4-6"   # 2단계 판정 모델 (속도/비용 vs 정밀도 조절)
SKILL_MD="$HOME/.claude/skills/humanizer-ko/SKILL.md"   # 2단계 판정 기준

input=$(cat)

# --- git commit 호출에만 반응 ---------------------------------------------
# jq가 없으면 원본 JSON 전체에서 찾는다.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || printf '%s' "$input")
case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# 우회: 환경변수 SKIP_AI_REVIEW=1, 또는 커밋 명령줄에 SKIP_AI_REVIEW=1 을 붙인 경우.
# (PreToolUse 훅은 자기 프로세스 env만 보므로 명령 문자열도 함께 검사한다.)
if [ "${SKIP_AI_REVIEW:-0}" = "1" ] || printf '%s' "$cmd" | grep -q 'SKIP_AI_REVIEW=1'; then
  exit 0
fi
command -v git >/dev/null 2>&1 || exit 0

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo_root" || exit 0

# --- 스테이징된 글(_posts/*.md)만 추린다 (bash 3.2 호환) -------------------
posts=()
while IFS= read -r line; do
  [ -n "$line" ] && posts+=("$line")
done < <(git diff --cached --name-only --diff-filter=ACM -- '_posts/*.md' 2>/dev/null)
[ "${#posts[@]}" -eq 0 ] && exit 0

# 본문만 남긴다: 프런트매터(첫 두 ---) 제거 + 코드펜스(```) 제거 + 표 줄 제거 + 인라인코드(`...`) 제거
# (표 셀은 평어체로 짧게 쓰는 게 이 블로그 문체라 어조 집계에서 뺀다 — .claude/blog-voice.md)
extract_body() {
  awk '
    BEGIN { fm = 0; code = 0 }
    /^---[[:space:]]*$/ { if (fm < 2) { fm++; next } }
    fm < 2 { next }
    /^[[:space:]]*```/ { code = !code; next }
    code { next }
    /^[[:space:]]*\|/ { next }
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
  # 평어체 "아니다."도 '니다'로 끝나므로 존댓말 집계에서 뺀다.
  formal=$((formal - $(printf '%s' "$body" | count '아니다[.!? ]')))
  plain_da=$(printf '%s' "$body" | count '다[.!?]')
  nida=$(printf '%s' "$body" | count '니다[.!?]')
  nida=$((nida - $(printf '%s' "$body" | count '아니다[.!?]')))
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
[ -f "$SKILL_MD" ] || exit 0                   # 스킬 없으면 1단계까지만 (fail-open)
VOICE_MD="$repo_root/.claude/blog-voice.md"    # 문체 견본 (「문체 보정」 샘플)

rubric="$(cat "$SKILL_MD")

---
위 humanizer-ko 지침을 검토 전용으로 적용한다. 글을 고쳐 쓰지 말고 판정만 해라.
- 아래 「블로그 문체 견본」을 「문체 보정」의 샘플로 삼는다. 견본에 있는 습관(합니다체 속 ~죠/~고요/~어요,
  표·소제목의 평어체 등)은 티로 보지 않는다. 견본 이전 글은 평어체로 일관되어 있으니, 한 문체로 일관된 글을
  견본과 다르다는 이유만으로 REVISE하지 않는다.
- 프런트매터, 코드 블록, Chirpy 프롬프트 박스 표기({: .prompt-tip } 등)는 판정 대상이 아니다.
- 「판정 지침」의 오탐 방지·밀도 기준을 따른다. 글을 지배하는 패턴 군집이 있을 때만 REVISE, 고립된 사례뿐이면 PASS.
첫 줄에 반드시 \"VERDICT: PASS\" 또는 \"VERDICT: REVISE\" 만 출력하고,
REVISE면 다음 줄부터 고칠 부분을 패턴 번호(§N)와 원문 구절을 붙여 짧은 불릿으로 적어라.

=== 블로그 문체 견본 ===
$(cat "$VOICE_MD" 2>/dev/null)"

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
