package com.pknu.spatium_backend.dto.member;

import jakarta.validation.constraints.NotBlank;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Data
// 멤버 회원가입 DTO
public class MemberSignupDTO {

    @NotBlank(message = "이메일을 입력해주세요")
    private String memEmail;

    private String memNick;
    
    private String memPass;

    private String memBir;

    private String memSex;

    private String memImg;

}
