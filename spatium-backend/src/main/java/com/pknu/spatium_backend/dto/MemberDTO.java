package com.pknu.spatium_backend.dto;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;


public class MemberDTO{

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    // 멤버 회원가입 DTO (POST /api/users)
    //  - 명세서의 요청 바디 필드명(email, nickname, password, birthDate, gender)과 동일하게 맞춤
    public static class MemberSignupDTO {

        @NotBlank(message = "이메일을 입력해주세요")
        private String email;

        private String nickname;

        private String password;

        private String birthDate;

        private String gender;

        // 이용약관 동의 (필수 : true여야 함)
        @AssertTrue(message = "이용약관에 동의해야 합니다")
        private boolean termsAgreed;

        // 개인정보처리방침 동의 (필수 : true여야 함)
        @AssertTrue(message = "개인정보처리방침에 동의해야 합니다")
        private boolean privacyAgreed;

    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    public static class MemberRequestDTO {

        private String userId;

        private String email;

        private String nickname;

        private String birthDate;

        private String gender;

        private String profileImageUrl;

        private String projectCount;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    // 소셜 로그인 DTO (POST /api/auth/social-sessions)
    //  - 보안 : 클라이언트가 보내는 email/providerUserId는 위조 가능하므로 받지 않는다.
    //    provider가 발급한 ID Token을 서버가 직접 검증해서 sub/email을 얻는다.
    public static class MemberSocialLoginDTO {

        // "GOOGLE", "APPLE" 등 소셜 제공자 구분
        @NotBlank(message = "provider 값이 필요합니다")
        private String provider;

        // provider가 발급한 ID Token (JWT) - 서버가 서명/iss/aud를 직접 검증함
        @NotBlank(message = "idToken 값이 필요합니다")
        private String idToken;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    // 소셜 회원가입 DTO (POST /api/auth/social-users)
    //  - 보안 : email/providerUserId는 서버가 ID Token을 검증해서 직접 얻는다.
    public static class MemberSocialSignupDTO {

        // "GOOGLE", "APPLE" 등 소셜 제공자 구분
        @NotBlank(message = "provider 값이 필요합니다")
        private String provider;

        // provider가 발급한 ID Token (JWT) - 서버가 서명/iss/aud를 직접 검증함
        @NotBlank(message = "idToken 값이 필요합니다")
        private String idToken;

        private String nickname;

        private String birthDate;

        private String gender;

        // 이용약관 동의 (필수 : true여야 함)
        @AssertTrue(message = "이용약관에 동의해야 합니다")
        private boolean termsAgreed;

        // 개인정보처리방침 동의 (필수 : true여야 함)
        @AssertTrue(message = "개인정보처리방침에 동의해야 합니다")
        private boolean privacyAgreed;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    // 로그인 요청 DTO (POST /api/auth/sessions)
    public static class LoginRequest {

        @NotBlank(message = "이메일을 입력해주세요")
        private String email;

        @NotBlank(message = "비밀번호를 입력해주세요")
        private String password;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    // 로그인 응답 DTO (POST /api/auth/sessions)
    public static class LoginResponse {

        private String accessToken;

        private String refreshToken;

        // 고정값 "Bearer"
        private String tokenType;

        // accessToken 만료 시간(초) : 3600
        private long expiresIn;

        private UserSummaryResponse user;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    // 로그인 응답의 user 요약 정보
    //  - 명세엔 userId가 숫자(1)지만, ERD상 mem_id가 VARCHAR2(36) UUID라 String으로 처리
    public static class UserSummaryResponse {

        private String userId;

        private String email;

        private String nickname;

        private String profileImageUrl;
    }
}