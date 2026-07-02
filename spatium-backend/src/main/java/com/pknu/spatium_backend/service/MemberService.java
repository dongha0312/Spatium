// MemberService.java
package com.pknu.spatium_backend.service;

import java.util.Map;
import java.util.HashMap;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.dto.MemberDTO.MemberSignupDTO;
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
            
            // 이건 멤버 컬럼에 없어서 없앰.
            // ,"createdAt", 
        );
    }

    public Map<String, Object> getMyInfo(String memId) {
        Member member = memberRepository.findById(memId)
            .orElseThrow(() -> new IllegalArgumentException("회원을 찾을 수 없습니다."));

        Map<String, Object> data = new HashMap<>();
        data.put("userId", member.getMem_id());
        data.put("email", member.getMem_email());
        data.put("nickname", member.getMem_nick());
        data.put("birthDate", member.getMem_bir());
        data.put("gender", member.getMem_sex());
        data.put("profileImageUrl", null);
        data.put("projectCount", 0);
        data.put("placedFurnitureCount", 0);

        return data;
    }

    @Transactional
    public void deleteUser(String memId, String password) {
        Member member = memberRepository.findById(memId)
            .orElseThrow(() -> new IllegalArgumentException("회원을 찾을 수 없습니다."));

        if (!member.getMem_pass().equals(password)) {
            throw new IllegalArgumentException("비밀번호가 일치하지 않습니다.");
        }

        memberRepository.delete(member);
    }
}
