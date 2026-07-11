package com.pknu.spatium_backend.model;

import java.time.LocalDateTime;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

// 발급된 refreshToken의 서버측 저장소 (로그아웃/재발급 시 무효화용)
//  - 토큰 원문이 아니라 SHA-256 해시만 저장한다 (DB 유출 시에도 토큰 복원 불가)
//  - revoked=true면 폐기된 토큰 : 재사용 시도는 탈취 신호로 간주함
@Entity
@Table(name = "refresh_token")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class RefreshToken {

    @Id
    private String token_id;

    private String mem_id;

    // refreshToken의 SHA-256 해시 (hex 64자)
    private String token_hash;

    private LocalDateTime expires_at;

    private boolean revoked;

    private LocalDateTime created_at;
}
