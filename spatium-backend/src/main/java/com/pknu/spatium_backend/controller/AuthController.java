package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CookieValue;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.auth.RefreshTokenCookieFactory;
import com.pknu.spatium_backend.dto.MemberDTO.LoginRequest;
import com.pknu.spatium_backend.dto.MemberDTO.LoginResponse;
import com.pknu.spatium_backend.dto.MemberDTO.TokenRefreshRequest;
import com.pknu.spatium_backend.service.MemberService;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/auth")
public class AuthController {

    private final MemberService memberService;
    private final RefreshTokenCookieFactory refreshTokenCookieFactory;

    @PostMapping(path = "/sessions")
    public ResponseEntity<?> postLogin(
            @Valid @RequestBody LoginRequest dto,
            HttpServletRequest request) {
        // brute-force 방어 키에 사용할 클라이언트 IP
        //  (리버스 프록시 뒤에 배포하면 X-Forwarded-For 처리 필요 - server.forward-headers-strategy)
        LoginResponse login = memberService.login(dto, request.getRemoteAddr());

        // refreshToken은 응답 바디 대신 httpOnly 쿠키로만 전달한다.
        //  - localStorage에 저장하지 않으므로 XSS로 스크립트가 실행돼도 탈취 불가
        ResponseCookie cookie = refreshTokenCookieFactory.create(login.getRefreshToken());
        login.setRefreshToken(null);

        return ResponseEntity.ok()
                .header(HttpHeaders.SET_COOKIE, cookie.toString())
                .body(Map.of(
                        "statusCode", 200,
                        "message", "로그인에 성공했습니다.",
                        "data", login));
    }

    // 토큰 재발급 : refreshToken으로 새 access/refresh 쌍 발급 (기존 refresh는 폐기됨)
    //  - 웹(브라우저) : httpOnly 쿠키의 refreshToken 사용 (바디 불필요)
    //  - 기타 클라이언트 호환 : 쿠키가 없으면 요청 바디의 refreshToken을 사용
    @PostMapping(path = "/token")
    public ResponseEntity<?> postTokenRefresh(
            @CookieValue(name = RefreshTokenCookieFactory.COOKIE_NAME, required = false) String cookieToken,
            @RequestBody(required = false) TokenRefreshRequest dto) {

        String refreshToken = (cookieToken != null && !cookieToken.isBlank())
                ? cookieToken
                : (dto == null ? null : dto.getRefreshToken());

        LoginResponse reissued = memberService.reissueTokens(refreshToken);

        // rotation된 새 refreshToken도 동일하게 httpOnly 쿠키로만 전달
        ResponseCookie cookie = refreshTokenCookieFactory.create(reissued.getRefreshToken());
        reissued.setRefreshToken(null);

        return ResponseEntity.ok()
                .header(HttpHeaders.SET_COOKIE, cookie.toString())
                .body(Map.of(
                        "statusCode", 200,
                        "message", "토큰이 재발급되었습니다.",
                        "data", reissued));
    }

    @DeleteMapping(path = "/sessions/current")
    public ResponseEntity<?> deleteLogout(@AuthenticatedMemId String memId) {
        // 서버에 저장된 refreshToken을 폐기해서 로그아웃이 실제 효력을 갖게 함
        memberService.logout(memId);

        // 브라우저의 refreshToken 쿠키도 즉시 만료(삭제)
        return ResponseEntity.noContent()
                .header(HttpHeaders.SET_COOKIE, refreshTokenCookieFactory.expire().toString())
                .build();
    }
}
