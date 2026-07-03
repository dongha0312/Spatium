package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialLoginDTO;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialSignupDTO;
import com.pknu.spatium_backend.service.MemberService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/auth")
public class MemberController {

    private final MemberService memberService;

    @PostMapping(path = "/social-sessions")
    public ResponseEntity<?> postSocialLogin(@RequestBody MemberSocialLoginDTO memDTO) {
        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "소셜 로그인에 성공했습니다.",
                "data", memberService.socialLogin(memDTO)));
    }

    @PostMapping(path = "/social-users")
    public ResponseEntity<?> postSocialSignup(@RequestBody MemberSocialSignupDTO memDTO) {
        return ResponseEntity.status(201).body(Map.of(
                "statusCode", 201,
                "message", "소셜 회원가입이 완료되었습니다.",
                "data", memberService.socialSignup(memDTO)));
    }
}
