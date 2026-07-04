---
title: "방송통신대학교 컴퓨터과학과 편입기 (2) 운영체제"
date: 2026-07-04 14:00:00 +0900
categories: [개발, 방송통신대학]
tags: [방송통신대학, 운영체제, 보안, JWT, 회고, CS]
---

운영체제는 막연히 자신 있는 과목이었다. PC는 윈도우랑 맥을 같이 쓰고, 폰도 안드로이드와 iOS를 다 굴려봤으니 "컴퓨터야 익숙하지" 싶었다. 그런데 막상 열어보니 그런 종류의 자신감으로 되는 과목이 아니었다.

그래도 정보처리기사를 준비하며 훑은 내용이 꽤 겹친 건 다행이었다. 가상 메모리, 페이지 교체 알고리즘, 스케줄링, 프로세스와 스레드 — 이런 단원은 배경지식이 있어 수월했고, 막연하던 자신감이 그나마 이유 있는 자신감으로 바뀌었다. 아는 단원은 더 깊이 파고, 처음 보는 단원은 최대한 많이 주워 담는 쪽으로 학기를 굴렸다. 운영체제 성적은 A0(94점)로 나왔다.

그중 제일 눈길이 간 건 14강, 운영체제 보안이었다. OS 본류에서 살짝 비켜난 주제이긴 한데, 요즘 기업 보안 사고 소식이 끊이지 않다 보니 자연스럽게 관심이 갔다. 그리고 공부하다 보니, 여기 나오는 개념 상당수가 [편입기 (1)]({% post_url 2026-06-16-knou-cs-transfer-1-discrete-math %}) 때처럼 이전 프로젝트에서 감으로 짜둔 인증 코드 위에 그대로 얹혔다.

## 보호와 보안, 그리고 인증·인가

강의는 보호와 보안을 먼저 갈라놓는다.

- **보호(Protection)** — 시스템 안의 자원을 서로 침범 못 하게 격리하는 메커니즘.
- **보안(Security)** — 인증과 암호화로 **합법적인 접근만** 이뤄지게 보장하는 상위 개념.

백엔드로 옮기면 익숙한 두 단어가 된다. "너 누구냐"를 확인하는 게 인증(Authentication), "그래서 뭘 할 수 있냐"를 따지는 게 인가(Authorization). OS가 말하는 "주체 식별·인증 → 접근제어"의 뼈대가 웹 인증 흐름과 그대로 같다.

문제는 그다음, **접근제어를 어떻게 저장하고 판정하느냐**다. 강의는 여기서 두 가지 구조를 준다. 그리고 이 둘이 내가 프로젝트에서 고른 인증 방식과 정확히 이어졌다.

## JWT는 결국 '권한 증명서'였다

강의에 나오는 **권한 리스트(Capability List)** 설명을 읽다가 멈칫했다. "각 주체마다 자신이 접근할 수 있는 객체와 권한을 마킹한 고유 증명서를 직접 소유한다." 이거, 내가 짠 JWT 발급 코드 그대로였다.

```java
public String createToken(Integer userId, String email, List<String> roles) {
    Claims claims = Jwts.claims().setSubject(email);
    claims.put("userId", userId);
    claims.put("roles", roles);   // 이 토큰 하나에 "이 주체가 가진 권한"을 통째로 담는다

    return Jwts.builder()
            .setClaims(claims)
            .setExpiration(validity)                       // 만료 시각도 토큰 안에
            .signWith(secretKey, SignatureAlgorithm.HS256) // 위조 못 하게 서명
            .compact();
}
```

`roles`를 토큰 안에 박아서 내보낸다. 그 뒤로 이 사용자는 요청마다 이 토큰을 들고 다니고, 서버는 토큰에 적힌 권한만 보고 판정한다. 권한 정보가 **서버가 아니라 주체 쪽에** 있는 것 — 강의에서 말한 Capability가 이거였다.

> **권한 리스트(Capability List)** — 접근제어 행렬을 주체 기준으로 쪼갠 구조. 각 주체가 "내가 접근할 수 있는 객체와 권한"을 적은 증명서를 직접 들고 다닌다.
{: .prompt-info }

## ACL이냐 Capability냐 = 세션이냐 JWT냐

강의는 Capability 옆에 **접근제어 리스트(ACL)** 를 나란히 둔다. 이건 반대로, 자원 객체마다 "나한테 접근할 수 있는 주체 목록"을 서버가 들고 있는 방식이다. 권한이 **서버 쪽에** 산다.

이 대비가 그대로 웹 인증 방식 두 개였다.

| 강의 개념 | 권한이 어디에 | 내 프로젝트 |
| :-- | :-- | :-- |
| 접근제어 리스트(ACL) | 서버가 보관 | 세션 인증 |
| 권한 리스트(Capability) | 주체가 지참 | JWT 토큰 |

세션은 서버가 로그인 상태를 쥐고 있어서, 서버 메모리(또는 세션 저장소)를 뒤지면 "이 사람 지금 뭐 할 수 있는지"가 나온다. JWT는 그 상태를 토큰에 담아 클라이언트한테 넘겨버린다. 어느 쪽이 낫다기보다, **권한을 누가 들고 있느냐가 다른 선택**이라는 게 강의를 듣고서야 또렷해졌다. 그땐 그냥 "MSA니까 stateless한 JWT" 정도로 골랐는데, 사실은 교과서에 이름이 붙어 있는 갈림길이었다.

## 모든 요청은 관문을 지난다

보안 커널 단원의 **참조 모니터(Reference Monitor)** 도 낯설지 않았다. "시스템에서 일어나는 모든 접근 요구를 중간에서 낚아채 보안 규칙을 판정하는" 장치인데, 우리 서비스에선 게이트웨이가 그 역할이었다. 모든 트래픽이 게이트웨이를 지나고, 거기 JWT 필터가 걸려 있다.

```java
public GatewayFilter apply(Config config) {
    return (exchange, chain) -> {
        String path = exchange.getRequest().getPath().value();

        if (isPublicPath(path)) {              // 화이트리스트면 검증 없이 통과
            return chain.filter(exchange);
        }

        String token = extractToken(exchange.getRequest());
        if (token == null || !validateToken(token)) {
            // 토큰이 없거나 위조면 여기서 401 — 뒤의 서비스로 넘어가지 못한다
            exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
            return writeError(exchange);
        }
        return chain.filter(exchange);          // 검증 통과한 요청만 뒤로 보낸다
    };
}
```

```text
                    ┌──────────────────────┐
   모든 요청 ──────▶│  게이트웨이 JWT 필터  │
                    └──────────┬───────────┘
              ┌────────────────┼────────────────┐
        화이트리스트         토큰 유효        토큰 무효·없음
      (/login, /signup)         │                 │
              └───────┬─────────┘                 ▼
                      ▼                         401 차단
                 서비스로 통과              (뒤로 못 넘어감)
```

강의는 참조 모니터의 필수 조건으로 **완전 중재(Complete Mediation)** 를 든다. "우회 경로가 존재해서는 안 된다. 모든 접근 요구가 예외 없이 관문을 관통해야 한다." 그런데 내 필터엔 예외가 있다. 로그인·회원가입처럼 토큰이 없어야 정상인 경로들이다.

```java
private static final List<String> PUBLIC_PATHS = Arrays.asList(
        "/api/core/auth/signup",
        "/api/core/auth/login",
        "/api/core/hobbies/**",   // 회원가입 화면에서 필요한 참조 데이터
        "/ws/**"
);
```

이 화이트리스트를 보고 나서 좀 서늘했다. 여기에 경로를 하나 잘못 넣거나 `/**` 같은 걸 실수로 열면, 그게 바로 인증을 건너뛰는 통로가 된다. 강의가 말한 "우회 경로"가 추상적인 경고가 아니라, 내 코드 한 줄이었던 거다.

> 참조 모니터의 대전제는 **모든 요청이 예외 없이 검증을 관통**하는 것이다. 화이트리스트에 경로 하나를 잘못 여는 순간, 그게 인증을 건너뛰는 우회 경로 — 곧 보안 구멍이 된다.
{: .prompt-danger }

## 그런데 로그아웃은? — 회수의 딜레마

Capability에는 강의가 짚어준 약점이 있다. 증명서를 주체가 들고 다니니, **한번 발급하면 회수가 어렵다**는 점이다. ACL은 서버가 목록을 쥐고 있어 한 줄 지우면 끝인데, Capability는 이미 손을 떠났다.

이걸 나는 로그아웃을 만들다가 몸으로 겪었다. 세션이면 서버에서 지우면 그만인데, JWT는 서명만 멀쩡하면 만료 전까지 계속 유효하다. 서버가 "이 토큰 이제 무효야"라고 말할 방법이 없었다. 그래서 무효화할 토큰을 서버가 따로 기억하는 블랙리스트를 뒀다.

```java
private final Map<String, Long> blacklistedTokens = new ConcurrentHashMap<>();

public void addToBlacklist(String token, Long expiry) {  // 로그아웃할 때 담아둔다
    blacklistedTokens.put(token, expiry);
}
public boolean isBlacklisted(String token) {             // 요청마다 걸러낸다
    return blacklistedTokens.containsKey(token);
}
```

만들 때는 그냥 "로그아웃하려면 이 수밖에 없네" 하고 짰다. 그런데 강의를 듣고 보니, 이건 회수가 쉬운 ACL의 성질을 Capability에 도로 덧댄 절충이었다. stateless하다고 골라 놓고, 정작 회수를 하려니 서버 상태(블랙리스트)를 다시 끌어들인 셈이다. 내가 감으로 밟았던 트레이드오프에 교과서가 뒤늦게 이름을 붙여줬다.

## 마무리

한 학기 지나고 보니, 보안 단원이 유독 오래 남았다. 인증 코드를 짤 때 나는 "되면 됐다"에 머물러 있었는데, 강의가 그 코드에 참조 모니터·완전 중재·Capability 회수 같은 이름표를 붙여주니 내가 뭘 하고 있었는지가 비로소 보였다.

요즘 뉴스에 나오는 보안 사고들도 멀리 있지 않았다. 관문을 안 거치는 우회 경로가 하나 있었거나, 필요 이상의 권한이 새어 나갔거나 — 대개 그 둘이다. 화이트리스트에 뭘 넣었는지, 로그아웃한 토큰이 정말 죽는지. 예전 같으면 넘겼을 것들을 이제는 한 번 더 들여다보게 됐다.

> 이론이 거창해 보여도, 결국 내가 감으로 짠 코드에 이름을 붙이고 구멍을 비춰주는 손전등이다. 그 이름표가 생기니 다음 설계에서 뭘 점검해야 할지가 먼저 떠오른다.
{: .prompt-tip }
