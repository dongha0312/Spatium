package com.pknu.spatium_backend.dto;

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
    // 멤버 회원가입 DTO
    public static class MemberSignupDTO {

        @NotBlank(message = "이메일을 입력해주세요")
        private String email;

        private String nickname;
        
        private String password;

        private String birthDate;

        private String gender;

        private boolean termsAgreed;

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
}