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
import lombok.extern.slf4j.Slf4j;

import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class MemberService {

    private final MemberRepository memberRepository;

    // 디폴트 이미지 위치.
    private static final String DEFAULT_PROFILE_IMAGE_URL = "http://localhost:8080/images/default-profile.png";

    // 일반 회원가입 기능
    @Transactional
    public Map<String, Object> postUserSignup(MemberSignupDTO memDTO) {

        if (memberRepository.existsByMemEmail(memDTO.getEmail())) {
            throw new IllegalArgumentException("이미 가입된 이메일입니다.");
        }

        log.info("service");

        Member member = Member.builder()
            .mem_id(UUID.randomUUID().toString())
            .mem_email(memDTO.getEmail())
            .mem_nick(memDTO.getNickname())
            .mem_pass(memDTO.getPassword())
            .mem_bir(memDTO.getBirthDate())
            .mem_sex(memDTO.getGender())
            .build();

        Member savedMember = memberRepository.save(member);

        Map<String, Object> data = new HashMap<>();
            data.put("userId", savedMember.getMem_id());
            data.put("email", savedMember.getMem_email());
            data.put("nickname", savedMember.getMem_nick());
            data.put("profileImageUrl", DEFAULT_PROFILE_IMAGE_URL);

            return data;
        }

    // 회원 조회
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
