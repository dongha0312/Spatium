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
    public static class MemberSocialLoginDTO {

        // "GOOGLE", "KAKAO" 등 소셜 제공자 구분
        @NotBlank(message = "provider 값이 필요합니다")
        private String provider;

        // 제공자 쪽 고유 사용자 ID (구글의 sub 등)
        //  - 참고 : ERD(Member 테이블)엔 이 값을 저장할 컬럼이 없어서, 현재는 받기만 하고 DB엔 저장 안 함
        @NotBlank(message = "providerUserId 값이 필요합니다")
        private String providerUserId;

        @NotBlank(message = "이메일을 입력해주세요")
        private String email;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    // 소셜 회원가입 DTO (POST /api/auth/social-users)
    public static class MemberSocialSignupDTO {

        // "GOOGLE", "KAKAO" 등 소셜 제공자 구분
        @NotBlank(message = "provider 값이 필요합니다")
        private String provider;

        // 제공자 쪽 고유 사용자 ID (구글의 sub 등)
        //  - 참고 : ERD(Member 테이블)엔 이 값을 저장할 컬럼이 없어서, 현재는 받기만 하고 DB엔 저장 안 함
        @NotBlank(message = "providerUserId 값이 필요합니다")
        private String providerUserId;

        @NotBlank(message = "이메일을 입력해주세요")
        private String email;

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
}