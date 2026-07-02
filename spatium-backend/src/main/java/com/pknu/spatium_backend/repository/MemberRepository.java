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
    //  - ERD엔 소셜 제공자쪽 고유ID(providerUserId)를 저장할 컬럼이 없어서,
    //    일반/소셜 회원 모두 이메일을 공통 식별 키로 사용함
    @Query("SELECT m FROM Member m WHERE m.mem_email = :memEmail")
    Optional<Member> findByMemEmail(@Param("memEmail") String memEmail);
}