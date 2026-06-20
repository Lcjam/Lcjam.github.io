---
title: "@Controller 쳤더니 4개가 떴다 — 스프링 컨트롤러 어노테이션 비교"
date: 2026-06-20 14:00:00 +0900
categories: [개발, Spring]
tags: [spring, controller, restcontroller, annotation]
media_subpath: /assets/img/posts/2026-06-20-spring-controller-annotations
---

컨트롤러 하나 만들려고 클래스 위에 `@Controller`라고 치는데, 자동완성에 비슷한 게 네 개나 떴다. `@Controller`, `@RestController`, `@ControllerAdvice`, `@RestControllerAdvice`. 그동안은 그냥 위에 두 개 중에 골라 쓰고, 아래 두 개는 예외 처리할 때 어디서 본 대로 따라 붙였다. 뭐가 어떻게 다른지 제대로 짚어본 적은 없었다.

![`@Controller`를 치자 자동완성에 뜬 네 개의 어노테이션](autocomplete.png)
_`@Controller` 하나 치려다 마주친 네 개. 패키지를 보면 `Controller`만 `stereotype`이고 나머지는 `web.bind.annotation`이다._

이름이 이렇게 닮은 데는 이유가 있겠지 싶어 한 번 파봤다. 파보니 네 개가 따로국밥이 아니라 두 개의 축으로 깔끔하게 갈리는 거였다.

## 사실 축은 두 개뿐이었다

이름만 보면 네 개가 다 제각각 같은데, 뜯어보면 기준은 딱 두 가지다.

- **요청을 직접 처리하느냐, 여러 컨트롤러에 공통으로 끼어드느냐** — 앞엣것이 `Controller`, 뒤엣것이 `Advice`다.
- **뷰 이름을 돌려주느냐, 데이터를 그대로 돌려주느냐** — 데이터를 돌려주는 쪽엔 이름에 `Rest`가 붙는다.

그러니까 `Rest`가 붙은 둘은 새로운 무언가가 아니라, 원래 있던 거에 `@ResponseBody`를 미리 합쳐둔 편의 어노테이션이다. 실제로 도입된 순서도 그렇다. `@ControllerAdvice`가 3.2, `@RestController`가 4.0, `@RestControllerAdvice`가 4.3에서 나왔다. 기본형이 먼저 있고, "매번 `@ResponseBody` 붙이기 귀찮으니까" 하고 합쳐준 버전이 나중에 따라온 셈이다.

하나씩 보자.

## @Controller — 뷰 이름을 돌려준다

가장 기본. 이 어노테이션이 붙은 클래스의 메서드는 기본적으로 **반환값을 뷰 이름으로 본다.**

```java
@Controller
public class HomeController {
    @GetMapping("/hello")
    public String hello() {
        return "hello"; // hello.html 같은 뷰를 찾아서 렌더링
    }
}
```

여기서 `return "hello"`는 문자열 "hello"를 그대로 응답하는 게 아니다. `hello`라는 이름의 뷰(Thymeleaf면 `hello.html`)를 찾아서 화면을 그려 보낸다. 서버가 HTML을 직접 말아서 내려주는 전통적인 방식, 그거다.

그럼 "여기서 화면 말고 데이터 자체를 보내고 싶으면?" 싶을 텐데, 그땐 메서드에 `@ResponseBody`를 따로 붙이면 된다.

```java
@Controller
public class HomeController {
    @GetMapping("/hello")
    @ResponseBody
    public String hello() {
        return "hello"; // 이제 문자열 "hello"가 응답 본문에 그대로
    }
}
```

> `@ResponseBody`가 붙는 순간, 반환값은 뷰 이름이 아니라 응답 본문 그 자체가 된다. 이 한 줄이 나머지 세 어노테이션을 푸는 열쇠다.
{: .prompt-info }

## @RestController — @Controller + @ResponseBody

방금 그 `@ResponseBody`를 메서드마다 붙이기 귀찮으니까, 클래스에 한 번에 발라준 게 `@RestController`다.

```java
@RestController
public class HelloController {
    @GetMapping("/hello")
    public String hello() {
        return "hello"; // @ResponseBody 안 붙여도 데이터로 나간다
    }
}
```

내부를 까보면 `@RestController`는 그냥 `@Controller`랑 `@ResponseBody`를 합쳐놓은 어노테이션이다. 그래서 이 안의 모든 메서드는 반환값이 자동으로 응답 본문이 된다. 객체를 돌려주면 알아서 JSON으로 바뀌어 나간다. 우리가 흔히 만드는 REST API가 이쪽이다.

비전공으로 시작해서 처음엔 이 둘이 그냥 다른 종류인 줄 알았는데, 사실은 후자가 전자에 한 겹 얹은 거였다.

## @ControllerAdvice — 여러 컨트롤러에 공통으로 끼어든다

여기서 축이 한 번 바뀐다. 위의 둘이 "요청을 직접 받는" 거였다면, `Advice`가 붙은 둘은 **요청을 직접 받지 않고, 여러 컨트롤러에 공통으로 끼어드는** 역할이다.

대표적인 게 예외 처리다. 컨트롤러마다 `try-catch`를 도배하는 대신, 한 군데 모아서 "이 예외가 터지면 이렇게 응답해라"를 전역으로 선언할 수 있다.

```java
@ControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(IllegalArgumentException.class)
    public String handle() {
        return "error"; // error.html 같은 에러 뷰로
    }
}
```

`@ControllerAdvice`도 기본은 `@Controller`처럼 반환값을 **뷰 이름**으로 본다. 그래서 위 코드는 에러 페이지(화면)를 보여주는 쪽이다. 예외 말고도 `@ModelAttribute`로 공통 모델 값을 넣거나 `@InitBinder`로 바인딩을 손볼 수도 있는데, 가장 많이 쓰는 건 역시 전역 예외 처리다.

## @RestControllerAdvice — @ControllerAdvice + @ResponseBody

`@ControllerAdvice`에 `@ResponseBody`를 합치면 `@RestControllerAdvice`다. 앞의 `@RestController`와 똑같은 패턴이다.

```java
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(IllegalArgumentException.class)
    public ErrorResponse handle(IllegalArgumentException e) {
        return new ErrorResponse(e.getMessage()); // JSON으로 내려간다
    }
}
```

`@RestController`로 API를 만들었으면, 예외가 터졌을 때도 에러 화면이 아니라 에러 JSON을 돌려줘야 앞단(프론트나 앱)에서 받아 쓰기 좋다. 그래서 REST API에서는 전역 예외 처리도 `@RestControllerAdvice`를 쓴다. 반환한 객체가 그대로 JSON 응답 본문이 되니까.

`@Controller`에 `@ResponseBody`를 얹은 게 `@RestController`였던 것과 똑같은 관계다. `Advice`쪽에 그대로 한 번 더 적용한 것뿐이다.

## 한눈에 정리

결국 표 하나로 들어간다.

| | 뷰 이름 반환 | 데이터(JSON) 반환 (+`@ResponseBody`) |
| :-- | :-- | :-- |
| **요청을 직접 처리** | `@Controller` | `@RestController` |
| **여러 컨트롤러에 공통 적용** | `@ControllerAdvice` | `@RestControllerAdvice` |

세로축은 "내가 요청을 직접 받느냐, 아니면 다른 컨트롤러들에 끼어드느냐", 가로축은 "뷰를 돌려주느냐, 데이터를 돌려주느냐". 오른쪽 칸 둘은 왼쪽 칸에 `@ResponseBody`가 더해진 버전이다.

처음엔 자동완성에 뜨는 네 개가 다 따로 외워야 할 별개의 무언가처럼 보였는데, 알고 보니 어노테이션 두 개를 합치고 안 합치고의 조합이었다. 이렇게 한 번 틀로 정리해두니, 다음에 컨트롤러 만들 때 자동완성에서 더는 안 헷갈릴 것 같다.

> 다음에 또 헷갈리면 두 가지만 묻자. 요청을 직접 받나, 다른 컨트롤러에 끼어드나? 그리고 화면을 주나, 데이터를 주나? 이 둘이면 네 개 중 하나로 떨어진다.
{: .prompt-tip }
