package com.pknu.spatium_backend.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import com.pknu.spatium_backend.model.Member;

public interface MemberRepository extends JpaRepository<Member, String> {

    @Query("SELECT COUNT(m) > 0 FROM Member m WHERE m.mem_email = :memEmail")
    boolean existsByMemEmail(@Param("memEmail") String memEmail);

    // 이메일로 회원 조회
    // 이메일은 가입 중복 확인과 일반 회원 조회 보조 키로 사용한다.
    @Query("SELECT m FROM Member m WHERE m.mem_email = :memEmail")
    Optional<Member> findByMemEmail(@Param("memEmail") String memEmail);

    @Query("SELECT m FROM Member m WHERE m.provider = :provider AND m.providerUserId = :providerUserId")
    Optional<Member> findByProviderAndProviderUserId(
            @Param("provider") String provider,
            @Param("providerUserId") String providerUserId);
}
