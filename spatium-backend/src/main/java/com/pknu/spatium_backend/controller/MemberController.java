package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.auth.RefreshTokenCookieFactory;
import com.pknu.spatium_backend.dto.MemberDTO.LoginResponse;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialLoginDTO;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialSignupDTO;
import com.pknu.spatium_backend.service.MemberService;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/auth")
public class MemberController {

    private final MemberService memberService;
    private final RefreshTokenCookieFactory refreshTokenCookieFactory;

    @PostMapping(path = "/social-sessions")
    public ResponseEntity<?> postSocialLogin(@Valid @RequestBody MemberSocialLoginDTO memDTO) {
        LoginResponse login = memberService.socialLogin(memDTO);

        // 일반 로그인과 동일 : refreshToken은 httpOnly 쿠키로만 전달 (바디 미포함)
        ResponseCookie cookie = refreshTokenCookieFactory.create(login.getRefreshToken());
        login.setRefreshToken(null);

        return ResponseEntity.ok()
                .header(HttpHeaders.SET_COOKIE, cookie.toString())
                .body(Map.of(
                        "statusCode", 200,
                        "message", "소셜 로그인에 성공했습니다.",
                        "data", login));
    }

    @PostMapping(path = "/social-users")
    public ResponseEntity<?> postSocialSignup(@Valid @RequestBody MemberSocialSignupDTO memDTO) {
        return ResponseEntity.status(201).body(Map.of(
                "statusCode", 201,
                "message", "소셜 회원가입이 완료되었습니다.",
                "data", memberService.socialSignup(memDTO)));
    }
}
