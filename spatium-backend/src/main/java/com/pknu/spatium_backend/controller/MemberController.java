package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialLoginDTO;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialSignupDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.service.MemberService;

import lombok.RequiredArgsConstructor;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

import com.pknu.spatium_backend.dto.MemberDTO;



@RestController
@RequiredArgsConstructor
@RequestMapping(path="/api/auth")
public class MemberController {

    private final MemberService memberService;

    // 소셜로그인 (POST /api/auth/social-sessions)
    @PostMapping(path = "/social-sessions")
    public ResponseEntity<?> postSocialLogin(@RequestBody MemberSocialLoginDTO memDTO) {
        try {
            return ResponseEntity.status(200).body(Map.of(
                "statusCode", 200,
                "message", "소셜 로그인에 성공했습니다.",
                "data", memberService.socialLogin(memDTO)
            ));
        } catch (ApiException e) {
            return buildErrorResponse(e);
        }
    }

    // 소셜회원가입 (POST /api/auth/social-users)
    @PostMapping(path = "/social-users")
    public ResponseEntity<?> postSocialSignup(@RequestBody MemberSocialSignupDTO memDTO) {
        try {
            return ResponseEntity.status(201).body(Map.of(
                "statusCode", 201,
                "message", "소셜 회원가입이 완료되었습니다.",
                "data", memberService.socialSignup(memDTO)
            ));
        } catch (ApiException e) {
            return buildErrorResponse(e);
        }
    }

    // 명세서의 공통 에러 응답 형식 : {statusCode, code, message, errors}
    private ResponseEntity<?> buildErrorResponse(ApiException e) {
        return ResponseEntity.status(e.getStatusCode()).body(Map.of(
            "statusCode", e.getStatusCode(),
            "code", e.getCode(),
            "message", e.getMessage(),
            "errors", java.util.List.of()
        ));
    }

}
