package com.pknu.spatium_backend.util;

import java.nio.charset.StandardCharsets;
import java.util.Date;

import javax.crypto.SecretKey;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

// JWT 토큰 생성/검증 유틸 (stateless 방식 : DB에 세션을 저장하지 않음)
//  - 로그인 : createAccessToken / createRefreshToken으로 토큰 발급
//  - 인증이 필요한 API : validateAccessTokenAndGetMemId로 검증 (access 전용)
//  - 토큰 재발급 API : validateRefreshTokenAndGetMemId로 검증 (refresh 전용)
//  - 두 토큰은 claim의 type("access"/"refresh")으로 구분되어 서로 용도를 바꿔 쓸 수 없다.
@Component
public class JwtUtil {

    // 토큰 용도 구분 claim
    private static final String TYPE_CLAIM = "type";
    private static final String TYPE_ACCESS = "access";
    private static final String TYPE_REFRESH = "refresh";

    // 서명용 비밀키 (HS256 기준 32바이트 이상 필요)
    //  - 실서비스라면 application.properties나 환경변수로 분리해야 함
    private final SecretKey key;

    // accessToken 만료 시간 : 3600초 (명세 기준)
    public static final long ACCESS_TOKEN_EXPIRES_IN = 3600;

    // refreshToken 만료 시간 : 14일
    private static final long REFRESH_TOKEN_EXPIRES_IN = 60L * 60 * 24 * 14;

    public JwtUtil(@Value("${spatium.jwt.secret}") String secret) {
        if (secret == null || secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException("spatium.jwt.secret must be at least 32 bytes for HS256.");
        }
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }

    // accessToken 생성 (subject에 mem_id 저장, type=access)
    public String createAccessToken(String memId) {
        return createToken(memId, ACCESS_TOKEN_EXPIRES_IN, TYPE_ACCESS);
    }

    // refreshToken 생성 (subject에 mem_id 저장, type=refresh, 만료만 더 김)
    public String createRefreshToken(String memId) {
        return createToken(memId, REFRESH_TOKEN_EXPIRES_IN, TYPE_REFRESH);
    }

    private String createToken(String memId, long expiresInSeconds, String tokenType) {
        Date now = new Date();
        Date expiry = new Date(now.getTime() + expiresInSeconds * 1000);

        return Jwts.builder()
                .subject(memId)
                .claim(TYPE_CLAIM, tokenType)
                .issuedAt(now)
                .expiration(expiry)
                .signWith(key)
                .compact();
    }

    // accessToken 검증 후 mem_id 반환 (API 인증용)
    //  - refreshToken을 API 인증에 쓰지 못하도록 type=access만 통과시킨다.
    public String validateAccessTokenAndGetMemId(String token) {
        return validateAndGetMemId(token, TYPE_ACCESS);
    }

    // refreshToken 검증 후 mem_id 반환 (토큰 재발급 API 전용)
    //  - accessToken으로는 재발급을 받지 못하도록 type=refresh만 통과시킨다.
    public String validateRefreshTokenAndGetMemId(String token) {
        return validateAndGetMemId(token, TYPE_REFRESH);
    }

    // 토큰 검증 후 mem_id 반환
    //  - 서명이 틀리거나, 만료됐거나, 형식이 이상하거나, type이 다르면 null 반환
    private String validateAndGetMemId(String token, String requiredType) {
        try {
            Claims claims = Jwts.parser()
                    .verifyWith(key)
                    .build()
                    .parseSignedClaims(token)
                    .getPayload();

            if (!requiredType.equals(claims.get(TYPE_CLAIM, String.class))) {
                return null;
            }

            return claims.getSubject();
        } catch (JwtException | IllegalArgumentException e) {
            return null;
        }
    }
}
