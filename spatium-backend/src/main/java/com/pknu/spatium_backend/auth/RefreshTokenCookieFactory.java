package com.pknu.spatium_backend.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseCookie;
import org.springframework.stereotype.Component;

import com.pknu.spatium_backend.util.JwtUtil;

// refreshToken을 담는 httpOnly 쿠키 생성기
//  - XSS로 스크립트가 실행되어도 httpOnly 쿠키는 JS에서 읽을 수 없으므로
//    localStorage 저장 방식보다 refreshToken 탈취 위험이 낮다.
//  - path를 /api/auth로 제한 : 재발급/로그아웃 요청에만 쿠키가 전송되고
//    일반 API 요청에는 불필요하게 실려가지 않는다.
@Component
public class RefreshTokenCookieFactory {

    public static final String COOKIE_NAME = "refreshToken";

    // HTTPS 운영 환경에서는 반드시 true로 설정 (평문 HTTP로 쿠키가 전송되지 않도록)
    //  - 로컬 개발(http://localhost)은 false가 아니면 쿠키가 저장되지 않아 기본값 false
    private final boolean secure;

    public RefreshTokenCookieFactory(@Value("${spatium.cookie.secure:false}") boolean secure) {
        this.secure = secure;
    }

    // 로그인/재발급 성공 시 : refreshToken 쿠키 발급
    public ResponseCookie create(String refreshToken) {
        return builder(refreshToken)
                .maxAge(JwtUtil.REFRESH_TOKEN_EXPIRES_IN)
                .build();
    }

    // 로그아웃 시 : 쿠키 즉시 만료(삭제)
    public ResponseCookie expire() {
        return builder("")
                .maxAge(0)
                .build();
    }

    private ResponseCookie.ResponseCookieBuilder builder(String value) {
        return ResponseCookie.from(COOKIE_NAME, value)
                .httpOnly(true)
                .secure(secure)
                .path("/api/auth")
                .sameSite("Lax");
    }
}
