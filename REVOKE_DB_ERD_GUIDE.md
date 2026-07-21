# 소셜 로그인 연결 해제(Revoke) - DB/ERD 작업 가이드

> 지금 당장 실행하는 문서가 아니라, 나중에 진행할 때 참고할 순서 정리본입니다.
> (2026-07-21 기준, Apple/Google revoke 구현 모두 보류 상태)
> Apple, Google 둘 다 같은 패턴이라 한 문서에 같이 정리했습니다.

## 1. 왜 필요한가

- 현재 회원 탈퇴(`MemberService.deleteUser()`)는 우리 DB 레코드만 지우고, Apple/Google 서버에는 아무 통보도 하지 않는다.
- 그 결과 탈퇴 후에도 사용자의 Apple/Google 계정 설정에는 "Spatium 연결됨" 상태가 그대로 남는다.
- Apple `/auth/revoke`, Google `oauth2.googleapis.com/revoke` API로 이 연결을 끊으려면, 로그인 시점에 발급받은 **refresh_token**을 서버에 저장해뒀다가 탈퇴 시점에 그 토큰으로 revoke를 호출해야 한다.
- 지금은 두 provider 모두 idToken만 받고 검증하는 구조라 이 refresh_token 자체가 없다 → **저장할 곳(컬럼)이 없다**가 이 문서의 출발점.
- 우선순위 참고 : Apple은 앱스토어 심사(가이드라인 5.1.1)에서 실제로 문제 삼는 경우가 있어 우선순위가 높고, Google은 상대적으로 덜 엄격하게 본다. 그래도 구조는 동일하므로 한 번에 같이 정리해둔다.

## 2. 변경 범위

- 건드리는 테이블: **`MEMBER`** 하나뿐
- `PROJECT` / `ROOM` / `furniture` / `REFRESH_TOKEN`(우리 서비스 자체 JWT용, 소셜 provider와 무관) 테이블은 손대지 않음
- 추가할 컬럼 2개 (둘 다 nullable):
  - `APPLE_REFRESH_TOKEN`
  - `GOOGLE_REFRESH_TOKEN`

> 컬럼을 provider별로 나눠서 각각 추가하는 방식(아래 3~7번)이 지금 상황(provider 2개)에는 가장 간단하다. 나중에 카카오 등 provider가 더 늘어날 걸 감안해서 처음부터 `MEMBER_SOCIAL_TOKEN(MEM_ID, PROVIDER, REFRESH_TOKEN)` 별도 테이블로 분리하는 설계도 있다 — 이건 9번(설계 대안)에 따로 정리해뒀다.

## 3. 실행 SQL

```sql
ALTER TABLE MEMBER ADD APPLE_REFRESH_TOKEN VARCHAR2(1000);
ALTER TABLE MEMBER ADD GOOGLE_REFRESH_TOKEN VARCHAR2(1000);
```

- 둘 다 nullable 컬럼 추가라서 기존 데이터(LOCAL/GOOGLE/APPLE 회원 전부)에는 영향 없음
- 크기(1000자)는 각 provider의 refresh_token을 넉넉히 담을 수 있는 여유치
- 두 컬럼을 한 번에 같이 실행해도 되고, Apple 것만 먼저/따로 실행해도 무방 (서로 독립적인 변경)

## 4. 프로젝트 컨벤션에 맞춘 실행 방법

이 프로젝트는 `spring.jpa.hibernate.ddl-auto=none`이라 스키마가 자동으로 반영되지 않는다. 기존에도 `spatium-backend/src/main/resources/migration_add_editable_bookcase.sql`처럼 SQL 파일을 만들어두고 Oracle(spatium 계정)에 **직접 접속해서 수동 실행**하는 방식을 쓰고 있으므로, 이번에도 같은 방식을 따른다.

1. `spatium-backend/src/main/resources/migration_add_social_refresh_tokens.sql` 같은 이름으로 위 두 `ALTER TABLE` 문을 저장해둔다.
2. 개발 DB(`application-dev.properties`에 있는 `210.119.12.115:1521/xe`, 계정 `spatium`)에 먼저 접속해서 실행.
3. 애플리케이션을 dev 프로필로 기동해서 정상 동작(회원 조회/로그인 등 기존 기능 포함) 확인.
4. 문제 없으면 운영 DB에도 동일 SQL 실행.

## 5. ERD 다이어그램 반영

DB에 컬럼을 추가한 뒤에는, 갖고 계신 ERD 툴(캡처하신 "Spatium_result" 다이어그램)의 `MEMBER` 엔티티 박스에도 똑같이 반영해서 실제 스키마와 문서가 어긋나지 않게 해야 한다.

1. `MEMBER` 테이블 박스를 연다.
2. 기존 `PROVIDER_USER_ID` 행 아래에 새 컬럼 행을 2개 추가한다.

   | 물리명                 | 논리명(예시)       | Domain                                                               | 데이터 타입      |
   | ---------------------- | ------------------ | -------------------------------------------------------------------- | ---------------- |
   | `APPLE_REFRESH_TOKEN`  | 애플 리프레시 토큰 | 다른 `VARCHAR2` 컬럼과 동일한 Domain 재사용(없으면 타입만 직접 지정) | `VARCHAR2(1000)` |
   | `GOOGLE_REFRESH_TOKEN` | 구글 리프레시 토큰 | 〃                                                                   | `VARCHAR2(1000)` |

3. 둘 다 PK/FK가 아니므로 왼쪽 열쇠 아이콘은 비워둔다 (`MEM_ID`, `PROVIDER_USER_ID`처럼 열쇠 아이콘 없는 일반 컬럼과 동일한 스타일).
4. 둘 다 nullable 컬럼이므로 `MEM_PASS`, `MEM_IMG`처럼 굵게 표시하지 않은 일반 행 스타일로 둔다 (PK인 `MEM_ID`만 굵게/강조).
5. 저장 후, `PROJECT` / `ROOM` / `furniture` / `REFRESH_TOKEN` 등 다른 테이블 박스와 그 사이 관계선(FK 라인)은 이번 변경과 무관하므로 건드리지 않는다.

> 순서 팁 : 실제 DB에 `ALTER TABLE`을 먼저 실행하고, 그 직후에 ERD 다이어그램을 업데이트하는 순서를 권장한다. 다이어그램만 먼저 고쳐두면 "문서상으로는 있는데 실제 DB엔 없는" 상태로 잠깐 어긋날 수 있다.

## 6. 엔티티(Member.java) 반영

컬럼 추가와 함께 아래 필드 2개를 추가해야 함 (지금은 하지 않음, 순서 참고용):

```java
@Column(name = "APPLE_REFRESH_TOKEN")
private String appleRefreshToken;

@Column(name = "GOOGLE_REFRESH_TOKEN")
private String googleRefreshToken;
```

## 7. 체크리스트

- [ ] 실행 전 `MEMBER` 테이블 백업(또는 최소 export)
- [ ] 개발 DB에서 먼저 실행 → 서버 정상 기동 확인
- [ ] 컬럼 추가만으로는 기존 회원 데이터에 영향 없음을 재확인
- [ ] ERD 다이어그램에도 `APPLE_REFRESH_TOKEN`, `GOOGLE_REFRESH_TOKEN` 행 반영
- [ ] 운영 DB 반영은 이 컬럼을 실제로 채우고 쓰는 백엔드 코드 배포와 시점을 맞춘다 (컬럼만 미리 추가해두는 건 문제 없음)

## 8. 롤백

```sql
ALTER TABLE MEMBER DROP COLUMN APPLE_REFRESH_TOKEN;
ALTER TABLE MEMBER DROP COLUMN GOOGLE_REFRESH_TOKEN;
```

- 롤백 시 ERD 다이어그램에서도 두 행을 함께 삭제해서 문서와 실제 스키마를 다시 맞춘다.

## 9. 설계 대안 (참고, 지금 채택 안 함)

provider가 카카오 등으로 계속 늘어날 가능성이 있다면, `MEMBER`에 컬럼을 계속 추가하는 대신 별도 테이블로 분리하는 방법도 있다.

```sql
CREATE TABLE MEMBER_SOCIAL_TOKEN (
    MEM_ID         VARCHAR2(36)   NOT NULL,
    PROVIDER       VARCHAR2(10)   NOT NULL,
    REFRESH_TOKEN  VARCHAR2(1000) NOT NULL,
    CREATED_AT     TIMESTAMP      DEFAULT SYSTIMESTAMP,
    CONSTRAINT PK_MEMBER_SOCIAL_TOKEN PRIMARY KEY (MEM_ID, PROVIDER),
    CONSTRAINT FK_MEMBER_SOCIAL_TOKEN_MEM FOREIGN KEY (MEM_ID) REFERENCES MEMBER (MEM_ID)
);
```

- 장점 : provider가 늘어나도 `MEMBER` 테이블/엔티티를 안 건드리고 행만 추가하면 됨
- 단점 : 테이블이 하나 늘고, 조회 시 조인이 하나 더 필요해짐
- 지금은 provider가 2개뿐이라 2번(컬럼 2개 추가) 방식이 더 간단해서 그쪽으로 정리했다. 나중에 provider가 3개 이상으로 늘어나는 시점에 이 대안으로 넘어가는 걸 고려하면 된다.

## 10. DB 작업 이후 남는 일 (참고용, 이 문서 범위 밖)

DB 컬럼만 추가한다고 revoke가 동작하는 건 아니고, provider별로 아래가 함께 필요하다.

**Apple**

1. `APPLE_TEAM_ID` / `APPLE_KEY_ID` / `APPLE_PRIVATE_KEY_B64`로 client_secret(JWT, ES256) 생성하는 백엔드 코드
2. 프론트엔드에서 Apple 로그인 시 `idToken`뿐 아니라 `authorization code`도 함께 백엔드로 전달
3. 백엔드가 그 code를 Apple `/auth/token`에 교환해서 refresh_token을 받아 `MEMBER.APPLE_REFRESH_TOKEN`에 저장
4. 회원 탈퇴(`deleteUser()`) 시 저장된 refresh_token으로 Apple `/auth/revoke` 호출 후 DB 삭제

**Google**

1. 프론트엔드 구글 로그인을 지금의 credential(ID Token) 방식에서, authorization code를 함께 받는 방식(예: `@react-oauth/google`의 `useGoogleLogin({ flow: 'auth-code' })`)으로 바꿔야 함
2. 백엔드가 그 code를 Google `/token` 엔드포인트에 교환해서 refresh_token을 받아 `MEMBER.GOOGLE_REFRESH_TOKEN`에 저장 (Google Client Secret 필요 — Google Cloud Console에서 별도 발급)
3. 회원 탈퇴(`deleteUser()`) 시 저장된 refresh_token으로 Google `oauth2.googleapis.com/revoke` 호출 후 DB 삭제

앱스토어에 낼 계획이 확정되면 Apple 쪽을 먼저, 이후 여유 있을 때 Google 쪽을 이어서 진행하면 된다.
