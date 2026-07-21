# 회원관리 보안 정리본

Spatium 백엔드(Spring)/프론트엔드(React) 기준, 일반 로그인·소셜 로그인·JWT 인증 관련 보안 설계 정리. iOS는 범위에서 제외.

---

## 1. 인증 처리 흐름

API 요청 한 건이 인증을 통과해 컨트롤러까지 도달하는 처리 순서.

1. **요청 전송** — 클라이언트가 `Authorization: Bearer <accessToken>` 헤더와 함께 API를 호출한다.
2. **토큰 검증** — `JwtAuthenticationFilter`가 매 요청마다 서명·만료·`type(access)`을 검증한다.
   ```java
   jwtUtil.validateAccessTokenAndGetMemId(token)
   ```
3. **인증 정보 등록** — 회원이 실존하면 `SecurityContext`에 인증 정보(principal = mem_id)를 저장한다.
   ```java
   if (memId != null && memberRepository.existsById(memId)) {
       setAuthentication(...);
   }
   ```
4. **인가 규칙 판단** — `SecurityConfig` 화이트리스트 대상이 아니면 인증 여부를 확인하고, 미인증 시 401을 반환한다.
5. **컨트롤러 진입** — `@AuthenticatedMemId`로 memId를 주입받아 비즈니스 로직을 수행한다.

파일: `spatium-backend/.../auth/JwtAuthenticationFilter.java`, `util/JwtUtil.java`, `auth/AuthenticatedMemIdArgumentResolver.java`

---

## 2. 비밀번호 보안

`BCryptPasswordEncoder`로 비밀번호를 해시로 저장하고, 평문은 절대 저장하지 않는다.

```java
// SecurityConfig.java
@Bean
public PasswordEncoder passwordEncoder() {
    return new BCryptPasswordEncoder();
}

// MemberService.java (회원가입)
.mem_pass(passwordEncoder.encode(memDTO.getPassword()))

// MemberService.java (로그인)
passwordEncoder.matches(dto.getPassword(), member.getMem_pass())
```

- `encode()`: 평문 비밀번호를 받아 BCrypt 해시 문자열(`$2a$10$...`)로 변환. 내부적으로 무작위 솔트를 생성해 비밀번호와 섞고, 여러 차례(cost factor) 반복 해시한 뒤 알고리즘 버전·cost·솔트·해시값을 하나의 문자열에 합쳐 반환한다. 솔트 생성/적용은 Spring Security 라이브러리 내부 동작이며 별도 자체 코드는 없다.
- `matches()`: 로그인 시 입력한 비밀번호를 저장된 해시와 비교. 원문 복호화가 불가능한 단방향 구조라, DB가 유출돼도 원문 비밀번호 복원이 사실상 불가능하다.

파일: `spatium-backend/.../config/SecurityConfig.java`, `service/MemberService.java`

---

## 3. 토큰 설계 — Access / Refresh Token

Access Token(1시간)과 Refresh Token(14일)을 이원화하고, 탈취 상황까지 고려해 설계했다.

### 3-1. 용도 분리 (type claim)

Access/Refresh 토큰에 `type` claim을 부여해 서로 용도를 바꿔 쓸 수 없도록 검증한다.

```java
// JwtUtil.java
private String validateAndGetMemId(String token, String requiredType) {
    try {
        Claims claims = Jwts.parser().verifyWith(key).build()
                .parseSignedClaims(token).getPayload();

        if (!requiredType.equals(claims.get(TYPE_CLAIM, String.class))) {
            return null;
        }
        return claims.getSubject();
    } catch (JwtException | IllegalArgumentException e) {
        return null;
    }
}
```

**왜 필요한가**: `JwtAuthenticationFilter`는 일반 API 요청을 인증할 때 서명·만료만 확인하고, DB의 refresh_token 테이블(폐기 여부)은 들여다보지 않는다. 그 DB 체크는 오직 `/api/auth/token`(재발급) 요청에서만 일어난다. type 구분이 없다면 탈취된 refresh token을 재발급 API 없이 그대로 access token처럼 써서 14일 동안 자유롭게 API를 호출할 수 있고, 이 사용은 DB 재사용탐지 로직을 전혀 거치지 않아 감지되지 않는다. type claim은 refresh token의 쓸모를 재발급 API 호출로만 한정시켜, 탈취되더라도 반드시 탐지 로직(아래 3-4)을 거치게 만드는 전제조건 역할을 한다. (즉 type 분리 자체가 탈취를 감지하는 것이 아니라, 탐지 로직이 반드시 작동하도록 강제하는 장치다.)

### 3-2. 해시 저장

Refresh Token은 원문이 아닌 SHA-256 해시로 DB에 저장한다 — 유출돼도 토큰 복원이 불가능하다.

```java
// RefreshTokenService.java
public void issue(String memId, String refreshToken) {
    refreshTokenRepository.revokeAllByMemId(memId);

    refreshTokenRepository.save(RefreshToken.builder()
        .token_id(UUID.randomUUID().toString())
        .mem_id(memId)
        .token_hash(sha256(refreshToken))
        .expires_at(LocalDateTime.now().plusSeconds(JwtUtil.REFRESH_TOKEN_EXPIRES_IN))
        .revoked(false)
        .build());
}

private String sha256(String value) {
    MessageDigest digest = MessageDigest.getInstance("SHA-256");
    return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
}
```

`revokeAllByMemId(memId)`가 먼저 실행되어 같은 회원의 기존 유효 토큰을 전부 폐기(`revoked=true`)한 뒤 새 토큰을 저장한다. 결과적으로 한 번에 하나의 refreshToken만 유효한 단일 세션 구조가 된다.

### 3-3. Rotation

재발급 시 기존 Refresh Token은 즉시 폐기하고, 새 토큰만 유효하게 유지한다.

```java
// RefreshTokenService.java
public void validateAndRevokeForRotation(String memId, String refreshToken) {
    RefreshToken stored = refreshTokenRepository.findByTokenHash(sha256(refreshToken))
        .orElseThrow(() -> new ApiException(401, "INVALID_REFRESH_TOKEN", "..."));

    if (stored.isRevoked()) {
        // 재사용 탐지 (3-4)
    }
    if (!stored.getMem_id().equals(memId) || stored.getExpires_at().isBefore(LocalDateTime.now())) {
        throw new ApiException(401, "INVALID_REFRESH_TOKEN", "...");
    }

    stored.setRevoked(true);         // 한 번 쓴 토큰은 즉시 폐기
    refreshTokenRepository.save(stored);
}
```
이후 `MemberService.reissueTokens()`가 `issue()`를 호출해 새 토큰을 저장한다.

### 3-4. 재사용 탐지

폐기된 토큰이 재사용되면 탈취 신호로 간주해 해당 회원의 토큰을 전량 폐기한다.

```java
if (stored.isRevoked()) {
    log.warn("폐기된 refreshToken 재사용 감지 (mem_id={})", stored.getMem_id());
    refreshTokenRepository.revokeAllByMemId(stored.getMem_id());
    throw new ApiException(401, "INVALID_REFRESH_TOKEN", "이미 사용된 refresh token입니다. 다시 로그인해주세요.");
}
```

파일: `spatium-backend/.../util/JwtUtil.java`, `service/RefreshTokenService.java`, `model/RefreshToken.java`, `repository/RefreshTokenRepository.java`

---

## 4. 토큰 저장 방식 — XSS 대응

토큰 종류에 따라 저장 위치를 분리해 탈취 경로를 최소화한다.

### 4-1. Access Token

- 브라우저 **localStorage**에 저장 (`authSession.js`의 `saveLoginSession`)
  ```js
  localStorage.setItem("spatium_auth", JSON.stringify(session));  // accessToken 포함
  ```
- API 요청 시 **axios 요청 인터셉터**가 모든 요청에 공통으로 Authorization 헤더를 자동 삽입한다. 개별 API 함수는 헤더를 직접 다루지 않는다.
  ```js
  // config/axiosInstance.js
  springApi.interceptors.request.use((config) => {
      const accessToken = getAccessToken();      // localStorage에서 매번 새로 읽음
      if (accessToken) config.headers.Authorization = `Bearer ${accessToken}`;
      return config;
  });
  ```
- 만료 1시간 — 탈취돼도 피해 범위가 제한적. 만료 시 응답 인터셉터가 401을 가로채 자동으로 재발급(`reissueTokens`) 후 원 요청을 1회 재시도하므로, 사용자 체감상 끊김은 없지만 내부적으로는 1시간마다 토큰이 교체된다.

### 4-2. Refresh Token

- **httpOnly 쿠키**로만 전달 — JS에서 읽기 불가 (`document.cookie`로 노출되지 않음). 응답 바디에서도 `login.setRefreshToken(null)`로 제거해 JSON에 값이 남지 않는다.
- `SameSite=Lax` 설정, `path`를 `/api/auth`로 제한 — 다른 사이트에서 시작된 요청(CSRF)에는 쿠키가 실리지 않고, 일반 API 요청(`/api/users/me` 등)에도 실려가지 않는다.
  ```java
  // RefreshTokenCookieFactory.java
  ResponseCookie.from("refreshToken", value)
      .httpOnly(true)
      .secure(secure)
      .path("/api/auth")
      .sameSite("Lax");
  ```
- XSS로 스크립트가 실행돼도 탈취 자체가 불가능 — 값을 읽을 방법이 없어 공격자가 빼돌려 재사용하는 시나리오가 막힌다(단, 페이지 내 스크립트가 같은 출처로 `/api/auth/*` 요청을 보내면 브라우저가 쿠키를 자동 첨부하긴 하나, 범위가 재발급/로그아웃으로 한정돼 있어 영향이 제한적).

파일: `spatium-backend/.../auth/RefreshTokenCookieFactory.java`, `spatium-frontend/src/utils/authSession.js`, `src/config/axiosInstance.js`

---

## 5. 소셜 로그인 보안

클라이언트가 보낸 값(email, providerUserId)은 신뢰하지 않고, 서버가 직접 ID Token을 검증한다.

### 5-1. 서버측 ID Token 검증

```java
Jwts.parser()
    .keyLocator(header -> locateKey(jwksUri, (ProtectedHeader) header))
    .build()
    .parseSignedClaims(idToken)
    .getPayload();
```
Google/Apple이 발급한 ID Token(JWT)의 서명을 각 provider의 JWKS 공개키로 서버가 직접 검증한다.

### 5-2. 발급자·대상 검증 (iss / aud)

토큰 발급자(`iss`)가 실제 provider인지, 대상(`aud`)이 우리 서비스의 클라이언트 ID인지 확인해 다른 서비스용 토큰의 재사용(replay)을 차단한다. `aud`는 콤마로 구분된 여러 클라이언트 ID(웹/iOS 등) 중 하나만 일치해도 통과한다 — 즉 "우리 앱"은 웹페이지 하나만이 아니라 등록해둔 모든 플랫폼 클라이언트를 포괄한다.

### 5-3. 알고리즘 강제 (RS256)

```java
if (!"RS256".equals(header.getAlgorithm())) {
    throw new JwtException("unsupported algorithm: " + header.getAlgorithm());
}
```
JWT 헤더의 `alg` 값을 그대로 신뢰하지 않고 RS256만 허용한다.

**RS256이란**: RSA 기반 비대칭키 서명 방식. 서명을 만드는 개인키(provider만 보유)와 검증하는 공개키(누구나 접근 가능, JWKS로 공개)가 분리되어 있다. 반면 우리 서비스 자체 JWT(`JwtUtil`)는 HS256(대칭키)을 쓰며, 서명·검증에 동일한 비밀키 하나를 사용한다.

**algorithm confusion 공격 방지**: RS256의 공개키는 원래 공개된 값이라 누구나 구할 수 있다. 만약 검증 로직이 헤더의 `alg`를 그대로 믿는다면, 공격자가 헤더를 `alg: HS256`으로 바꾸고 그 공개키 값을 HS256의 "비밀키"인 것처럼 사용해 서명을 위조할 수 있다. 헤더의 alg를 무시하고 RS256을 강제하면 이런 알고리즘 바꿔치기 시도 자체가 차단된다.

파일: `spatium-backend/.../auth/SocialIdTokenVerifier.java`

---

## 6. Brute-force · 어뷰징 방어

반복 요청 기반 공격을 시도 횟수 제한으로 완화한다.

### 6-1. 로그인 시도 제한

- 이메일 + IP 조합(`email + "|" + clientIp`)으로 실패 횟수를 추적한다.
- 5회 연속 실패 시 5분간 계정 잠금(429).
  ```java
  Instant lockedUntil = failures >= MAX_FAILURES ? now.plus(LOCK_DURATION) : null;
  ```
- 로그인 성공 시 실패 기록을 초기화한다.

### 6-2. 회원가입 Rate Limit

- 동일 IP의 가입 시도를 10분당 10회로 제한한다.
  ```java
  if (window.count() > MAX_ATTEMPTS) {
      throw new ApiException(429, "TOO_MANY_ATTEMPTS", ...);
  }
  ```
- 이메일 존재 여부 무단 조회 방지 — "이미 가입된 이메일입니다" 응답을 반복 조회해 특정 이메일의 가입 여부를 캐내는 계정 열거(enumeration) 시도를 완화한다.
- 봇의 대량 계정 생성(스팸 가입) 시도도 같은 제한으로 억제된다.

인메모리(`ConcurrentHashMap`) 방식이라 단일 서버 배포 기준이며, 다중 서버로 확장 시 Redis 등 공유 저장소로 교체가 필요하다.

파일: `spatium-backend/.../auth/LoginAttemptLimiter.java`, `auth/SignupRateLimiter.java`

---

## 7. 인가 정책 · 에러 응답 처리

Spring Security 설정으로 접근 제어와 응답 형식을 일관되게 관리한다.

### 7-1. Stateless 정책 · CSRF/폼로그인 비활성화

```java
.csrf(AbstractHttpConfigurer::disable)
.formLogin(AbstractHttpConfigurer::disable)
.httpBasic(AbstractHttpConfigurer::disable)
.sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
```
JWT 기반 인증이므로 세션을 만들지 않는다. CSRF는 "로그인 세션 쿠키를 이용해 사용자 모르게 다른 사이트가 요청을 대신 보내는" 공격인데, 이 서비스는 세션 쿠키가 아니라 프론트 코드가 직접 넣는 Authorization 헤더로 인증하므로 CSRF 공격의 전제 자체가 성립하지 않아 비활성화했다.

### 7-2. 요청별 인가 규칙 (화이트리스트)

```java
.requestMatchers(HttpMethod.POST, "/api/auth/sessions").permitAll()
.requestMatchers("/api/auth/social-*").permitAll()
.requestMatchers(HttpMethod.POST, "/api/auth/token").permitAll()
.requestMatchers(HttpMethod.GET, "/api/furniture").permitAll()
...
.anyRequest().authenticated()
```
가입/로그인/소셜인증/재발급/공개 카탈로그 등 최소 API만 허용 목록에 올리고, 나머지는 전부 인증이 필요하다. **화이트리스트 방식**은 "허용할 것만 등록하고 나머지는 기본적으로 차단"하는 구조라, 새 API를 추가할 때 실수로 등록을 빠뜨려도 기본값이 "인증 필요"라 안전한 쪽으로 유지된다(블랙리스트 방식은 반대로 실수 시 의도치 않게 공개돼버릴 위험이 있다).

### 7-3. 401 응답 포맷 통일

미인증 요청은 공통 에러 스펙(`{statusCode, code, message, errors}`)으로 401 응답을 내려준다. CORS preflight(OPTIONS)와 에러 디스패치(`/error`)는 예외적으로 인증 없이 통과시킨다.

파일: `spatium-backend/.../config/SecurityConfig.java`

---

## 8. 파일 업로드 보안

룸 스캔 파일(.usdz), 프로필 이미지 업로드 시 크기·형식·경로를 서버가 직접 검증한다.

- **요청 크기 제한**: 전역 multipart 설정으로 개별/전체 요청 용량 상한을 둔다.
  ```
  spring.servlet.multipart.max-file-size=100MB
  spring.servlet.multipart.max-request-size=110MB
  ```
- **확장자 + 실제 콘텐츠 이중 검증**: 확장자만 확인하지 않고 매직바이트로 실제 파일 형식까지 재검증해 위조 파일을 차단한다.
  ```java
  requireFileExtension(file, ".usdz", "3D 모델");
  requireUsdzContent(file);   // 첫 4바이트가 zip 매직바이트(PK\x03\x04)인지 확인
  ```
- **경로 조작(Path Traversal) 방지**: 파일명을 안전한 문자로 치환하고, 저장 경로가 지정 폴더를 벗어나지 않는지 검증한다.
  ```java
  ensureInside(saveDir, filePath);   // 상위 폴더 이탈 시 400 처리
  ```

> 참고: 이 항목은 `RoomService`(프로젝트/룸 도메인) 코드 기준이며, 순수 회원(Member) 도메인의 파일 업로드는 프로필 이미지 업로드(`MemberService.updateAvatar`, content-type 체크만 수행)로 검증 수준이 더 단순하다.

파일: `spatium-backend/.../service/RoomService.java`

---

## 9. 사용자별 데이터 접근 제어 (IDOR 방지)

인증된 사용자라도 남의 프로젝트/룸에는 접근할 수 없도록 소유권을 서비스 계층에서 재확인한다.

- **소유권 검증**: 요청한 projectId가 실제 로그인한 회원의 소유인지 확인, 아니면 403.
  ```java
  if (!memId.equals(project.getProj_mem())) {
      throw new ApiException(403, "FORBIDDEN", "해당 프로젝트에 접근할 권한이 없습니다.");
  }
  ```
- **프로젝트 → 룸 이중 확인**: 룸 단건 접근 시에도 상위 프로젝트 소유권부터 확인해, URL의 roomId만 바꿔 남의 데이터에 접근하는 것을 차단한다.
  ```java
  getOwnedProject(memId, projectId);
  Room room = getOwnedRoom(memId, roomId);
  ```
- **탈퇴 시 개인 데이터까지 정리**: 회원 탈퇴 시 프로젝트/룸 레코드와 서버에 저장된 스캔 파일까지 함께 삭제한다.
  ```java
  refreshTokenService.deleteAll(memId);
  projectService.deleteAllByMember(memId);
  ```

### IDOR 예시

인증만 확인하고 소유권을 확인하지 않으면 벌어지는 상황:
1. 사용자 A(`mem_id="u-111"`)의 프로젝트 ID는 `"proj-abc"`.
2. 사용자 B(`mem_id="u-222"`, 정상 로그인된 다른 회원)가 어떤 경로로든 A의 projectId를 알게 되어, 자신의 정상 accessToken을 그대로 사용하되 요청의 projectId만 `"proj-abc"`로 바꿔 호출.
3. 소유권 검증이 없다면 서버는 "토큰이 유효한가?"만 확인하고 A의 데이터를 그대로 B에게 반환한다.
4. 실제로는 `memId("u-222").equals(project.getProj_mem()="u-111")`이 false이므로 403이 반환되어 차단된다.

즉 IDOR는 "로그인 자체는 진짜인데, 요청한 리소스가 그 로그인한 사람의 것인지 확인하지 않아서 뚫리는" 취약점이다.

파일: `spatium-backend/.../service/RoomService.java`, `service/MemberService.java`

---

## 10. SQL Injection · XSS 대응

쿼리는 파라미터 바인딩만, 사용자 입력은 검증 후 저장한다.

### 10-1. SQL Injection

**1) JPQL 파라미터 바인딩으로 작성**
```java
@Query("SELECT r FROM RefreshToken r WHERE r.token_hash = :tokenHash")
Optional<RefreshToken> findByTokenHash(@Param("tokenHash") String tokenHash);
```
`:tokenHash`는 값이 들어올 자리를 표시할 뿐, 쿼리 문자열 자체는 사용자가 뭘 보내든 절대 바뀌지 않는다. `tokenHash` 값은 쿼리 텍스트에 합쳐지지 않고 별도 경로(메서드 인자 → JPA/하이버네이트 → DB 드라이버)로 전달되며, DB는 이 값을 항상 "비교할 데이터"로만 처리하고 SQL 문법의 일부로 해석하지 않는다. 그래서 입력값에 어떤 특수문자나 SQL 예약어가 들어와도 쿼리의 의미 자체를 바꿀 수 없다.

**위험한 방식과 비교**:
```java
// 쓰지 않음 — 문자열을 직접 이어붙이는 방식
"WHERE token_hash = '" + tokenHash + "'"
```
이렇게 짜면 `tokenHash`에 `' OR '1'='1`이 들어왔을 때 최종 쿼리가 `WHERE token_hash = '' OR '1'='1'`이 되어 조건이 무력화되고, 데이터가 통째로 조회될 수 있다.

**2) 네이티브 쿼리 문자열 조합 금지**
JPA에서는 JPQL 대신 순수 SQL을 직접 쓰는 네이티브 쿼리(`@Query(nativeQuery = true)`)도 쓸 수 있는데, 이때 문자열을 직접 이어붙이면 1번의 방어 효과가 그대로 무력화된다. 그래서 "네이티브 쿼리를 아예 쓰지 않는다"가 아니라, "쓰더라도 문자열 조합 없이 파라미터 바인딩으로만 작성한다"는 원칙을 지킨다.

**3) 입력값은 저장 전 Bean Validation으로 형식 우선 검증**
```java
@NotBlank
@Email
private String email;

@Pattern(regexp = "^[A-Za-z0-9]{8,20}$")
private String password;
```
요청이 서비스 로직/DB에 도달하기 전에 DTO 단계에서 값의 형식을 검사한다. `@NotBlank`는 빈 값/공백만 있는 값을 거부하고, `@Email`은 이메일 형식이 아니면 거부하며, `@Pattern`은 정규식으로 허용된 문자만 통과시킨다. 형식에 안 맞으면 DB 쿼리까지 가지 않고 컨트롤러 단에서 바로 400으로 반환된다. 1·2번이 "쿼리 레벨" 방어라면, 3번은 "입력 레벨"에서 애초에 의심스러운 값을 걸러내는 1차 필터다.

### 10-2. XSS

**1) 사용자 입력을 `dangerouslySetInnerHTML` 등으로 직접 렌더링하지 않음**
```jsx
// 쓰지 않음
<div dangerouslySetInnerHTML={{ __html: userInput }} />
```
React에서 사용자 입력값을 실제 HTML로 그대로 렌더링해주는 기능이다. 이걸 쓰면 `userInput`에 `<script>...</script>` 같은 값이 들어와도 브라우저가 진짜 HTML/스크립트로 인식해 그대로 실행한다. 예를 들어 프로필 소개글이나 댓글에 악성 스크립트를 심어두면, 그 글을 보는 다른 사용자의 브라우저에서 스크립트가 실행돼 로그인 정보를 훔쳐갈 수 있다. Spatium은 이 기능 자체를 쓰지 않는다.

**2) React가 텍스트 렌더링 시 기본적으로 이스케이프 처리**
`{userInput}` 형태로 값을 출력하면 React가 `<`, `>`, `&` 같은 HTML 특수문자를 자동으로 이스케이프해, 값이 화면에는 항상 "코드"가 아닌 "글자"로만 표시된다. 예를 들어 `userInput`이 `<script>alert(1)</script>`라면, `dangerouslySetInnerHTML`로는 진짜 스크립트로 실행되지만 `{userInput}`으로는 문자 그대로 텍스트로만 보이고 실행되지 않는다. 1번 기능만 쓰지 않으면 이 방어가 자동으로 적용된다.

**3) Refresh Token은 httpOnly 쿠키라 스크립트 실행돼도 탈취 자체가 불가능**
1·2번을 뚫고 악성 스크립트가 실행되는 최악의 상황을 가정해도, `document.cookie`로는 httpOnly로 설정된 쿠키를 읽을 수 없어 Refresh Token은 여전히 안전하다(4-2 참고). Access Token은 localStorage에 저장돼 이론상 XSS에 노출될 수 있는데, 그래서 만료 시간을 1시간으로 짧게 잡아 피해 범위를 제한한다(4-1 참고).

파일: `spatium-backend/.../repository/RefreshTokenRepository.java`, `dto/MemberDTO.java`

---

## 11. 트러블슈팅 — 인증 및 사용자 식별

**문제**: 일반/Google/Apple 로그인을 하나의 회원 테이블로 통합해야 했는데, 이메일만으로 식별하면 provider 간 이메일 중복 가능성, Apple의 이메일 비공개 선택 시 식별 불가 상황이 발생할 수 있었다.

**해결**: `Member`에 `provider` + `provider_user_id` 컬럼을 별도로 두고, LOCAL은 이메일을, 소셜은 provider가 발급한 sub 값을 식별 키로 저장한다.
```java
memberRepository.findByProviderAndProviderUserId(verified.provider(), verified.providerUserId())
```
Access/Refresh Token은 내부 `mem_id`(UUID) 기준으로 발급해 provider와 무관하게 동일한 토큰 체계를 유지한다.

> **쉽게 말하면**: 로그인 방법(일반/Google/Apple)이 달라도, 로그인에 성공하고 나면 그 이후부터는 모두 똑같은 방식으로 토큰을 발급하고 관리한다. 로그인 시점에는 provider별로 식별 방법이 다르지만(이메일 vs provider의 sub 값), 일단 로그인에 성공하면 내부적으로 부여된 고유 ID인 `mem_id` 하나만 기준으로 토큰을 발급해 하나의 토큰 체계로 통합 관리한다. 즉 "로그인 방법은 여러 개, 로그인 이후 토큰 관리는 하나로 통일"이라는 뜻이다.

파일: `spatium-backend/.../model/Member.java`, `service/MemberService.java`

---

## 참고: 관련 파일 목록

```
spatium-backend/src/main/java/com/pknu/spatium_backend/
├── auth/
│   ├── AuthenticatedMemId.java
│   ├── AuthenticatedMemIdArgumentResolver.java
│   ├── JwtAuthenticationFilter.java
│   ├── LoginAttemptLimiter.java
│   ├── RefreshTokenCookieFactory.java
│   ├── SignupRateLimiter.java
│   └── SocialIdTokenVerifier.java
├── config/SecurityConfig.java
├── controller/AuthController.java
├── model/RefreshToken.java, Member.java
├── repository/RefreshTokenRepository.java
├── service/RefreshTokenService.java, MemberService.java, RoomService.java
├── util/JwtUtil.java
└── dto/MemberDTO.java

spatium-frontend/src/
├── pages/member/LoginPage.js
├── routers/AuthRouters.js
├── styles/loginpage.css
├── utils/authSession.js
├── config/axiosInstance.js
└── springApi/MemberSpringBootApi.js
```
