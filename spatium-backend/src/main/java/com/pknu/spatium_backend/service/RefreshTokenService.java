package com.pknu.spatium_backend.service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.HexFormat;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.model.RefreshToken;
import com.pknu.spatium_backend.repository.RefreshTokenRepository;
import com.pknu.spatium_backend.util.JwtUtil;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

// refreshToken의 서버측 저장/폐기 관리
//  - 발급 : 로그인/재발급 시 해시를 저장 (같은 회원의 기존 토큰은 폐기 = 단일 세션)
//  - 검증 : 재발급 요청 시 저장된 유효 토큰인지 확인하고 폐기(rotation)
//  - 폐기 : 로그아웃 시 전부 revoked, 탈퇴 시 레코드 삭제
@Service
@RequiredArgsConstructor
@Slf4j
public class RefreshTokenService {

    private final RefreshTokenRepository refreshTokenRepository;

    // 새 refreshToken 저장 (같은 회원의 기존 유효 토큰은 전부 폐기)
    @Transactional
    public void issue(String memId, String refreshToken) {
        refreshTokenRepository.revokeAllByMemId(memId);

        refreshTokenRepository.save(RefreshToken.builder()
                .token_id(UUID.randomUUID().toString())
                .mem_id(memId)
                .token_hash(sha256(refreshToken))
                .expires_at(LocalDateTime.now().plusSeconds(JwtUtil.REFRESH_TOKEN_EXPIRES_IN))
                .revoked(false)
                .created_at(LocalDateTime.now())
                .build());
    }

    // 재발급용 검증 : 저장된 유효 토큰이면 폐기(rotation)하고 통과, 아니면 401
    //  - 의도적으로 @Transactional을 붙이지 않음 : 재사용 탐지 시의 전체 폐기가
    //    아래에서 던지는 예외에 의해 롤백되지 않고 즉시 반영되어야 하기 때문
    public void validateAndRevokeForRotation(String memId, String refreshToken) {
        RefreshToken stored = refreshTokenRepository.findByTokenHash(sha256(refreshToken))
                .orElseThrow(() -> new ApiException(401, "INVALID_REFRESH_TOKEN",
                        "유효하지 않은 refresh token입니다."));

        if (stored.isRevoked()) {
            // 이미 폐기된 토큰의 재사용 = 탈취 신호로 간주하고 해당 회원의 토큰 전부 폐기
            log.warn("폐기된 refreshToken 재사용 감지 (mem_id={})", stored.getMem_id());
            refreshTokenRepository.revokeAllByMemId(stored.getMem_id());
            throw new ApiException(401, "INVALID_REFRESH_TOKEN",
                    "이미 사용된 refresh token입니다. 다시 로그인해주세요.");
        }

        if (!stored.getMem_id().equals(memId)
                || stored.getExpires_at().isBefore(LocalDateTime.now())) {
            throw new ApiException(401, "INVALID_REFRESH_TOKEN", "유효하지 않은 refresh token입니다.");
        }

        // rotation : 한 번 사용된 refreshToken은 즉시 폐기 (새 토큰은 issue()가 저장)
        stored.setRevoked(true);
        refreshTokenRepository.save(stored);
    }

    // 로그아웃 : 해당 회원의 refreshToken 전부 폐기
    public void revokeAll(String memId) {
        refreshTokenRepository.revokeAllByMemId(memId);
    }

    // 회원 탈퇴 : 해당 회원의 refreshToken 레코드 삭제
    public void deleteAll(String memId) {
        refreshTokenRepository.deleteAllByMemId(memId);
    }

    // 토큰 원문 저장 금지 : SHA-256 해시(hex)로 변환
    private String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            // JVM 표준 알고리즘이라 발생하지 않음
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }
}
