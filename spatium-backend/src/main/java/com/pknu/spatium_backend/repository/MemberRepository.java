package com.pknu.spatium_backend.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import com.pknu.spatium_backend.model.Member;

public interface MemberRepository extends JpaRepository<Member, String> {

    @Query("SELECT COUNT(m) > 0 FROM Member m WHERE m.mem_email = :memEmail")
    boolean existsByMemEmail(@Param("memEmail") String memEmail);
}