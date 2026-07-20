package com.pknu.spatium_backend.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import com.pknu.spatium_backend.model.RefreshToken;

public interface RefreshTokenRepository extends JpaRepository<RefreshToken, String> {

    @Query("SELECT r FROM RefreshToken r WHERE r.token_hash = :tokenHash")
    Optional<RefreshToken> findByTokenHash(@Param("tokenHash") String tokenHash);

    // 해당 회원의 유효한 refreshToken을 전부 폐기 (로그아웃, 재사용 탐지, 새 로그인 시)
    @Transactional
    @Modifying
    @Query("UPDATE RefreshToken r SET r.revoked = true WHERE r.mem_id = :memId AND r.revoked = false")
    int revokeAllByMemId(@Param("memId") String memId);

    // 해당 회원의 refreshToken 레코드 전부 삭제 (회원 탈퇴 시)
    @Transactional
    @Modifying
    @Query("DELETE FROM RefreshToken r WHERE r.mem_id = :memId")
    void deleteAllByMemId(@Param("memId") String memId);
}
