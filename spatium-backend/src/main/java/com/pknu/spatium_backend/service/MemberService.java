// MemberService.java
package com.pknu.spatium_backend.service;

import java.util.Map;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.dto.member.MemberSignupDTO;
import com.pknu.spatium_backend.model.Member;
import com.pknu.spatium_backend.repository.MemberRepository;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class MemberService {

    private final MemberRepository memberRepository;

    @Transactional
    public Map<String, Object> postUserSignup(MemberSignupDTO memDTO) {

        if (memberRepository.existsByMemEmail(memDTO.getMemEmail())) {
            throw new IllegalArgumentException("이미 가입된 이메일입니다.");
        }

        Member member = Member.builder()
            .mem_id(UUID.randomUUID().toString())
            .mem_email(memDTO.getMemEmail())
            .mem_nick(memDTO.getMemNick())
            .mem_pass(memDTO.getMemPass())
            .mem_bir(memDTO.getMemBir())
            .mem_sex(memDTO.getMemSex())
            .build();

        Member savedMember = memberRepository.save(member);

        return Map.of(
            "userId", savedMember.getMem_id(),
            "email", savedMember.getMem_email(),
            "nickname", savedMember.getMem_nick()
        );
    }
}