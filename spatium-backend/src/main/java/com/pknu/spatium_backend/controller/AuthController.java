package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.dto.MemberDTO.LoginRequest;
import com.pknu.spatium_backend.dto.MemberDTO.TokenRefreshRequest;
import com.pknu.spatium_backend.service.MemberService;

import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/auth")
public class AuthController {

    private final MemberService memberService;

    @PostMapping(path = "/sessions")
    public ResponseEntity<?> postLogin(
            @RequestBody LoginRequest dto,
            HttpServletRequest request) {
        // brute-force 방어 키에 사용할 클라이언트 IP
        //  (리버스 프록시 뒤에 배포하면 X-Forwarded-For 처리 필요 - server.forward-headers-strategy)
        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "로그인에 성공했습니다.",
                "data", memberService.login(dto, request.getRemoteAddr())));
    }

    // 토큰 재발급 : refreshToken으로 새 access/refresh 쌍 발급 (기존 refresh는 폐기됨)
    @PostMapping(path = "/token")
    public ResponseEntity<?> postTokenRefresh(@RequestBody TokenRefreshRequest dto) {
        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "토큰이 재발급되었습니다.",
                "data", memberService.reissueTokens(dto.getRefreshToken())));
    }

    @DeleteMapping(path = "/sessions/current")
    public ResponseEntity<?> deleteLogout(@AuthenticatedMemId String memId) {
        // 서버에 저장된 refreshToken을 폐기해서 로그아웃이 실제 효력을 갖게 함
        memberService.logout(memId);
        return ResponseEntity.noContent().build();
    }
}
