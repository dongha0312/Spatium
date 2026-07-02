// MemberService.java
package com.pknu.spatium_backend.service;

import java.util.Map;
import java.util.HashMap;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.dto.MemberDTO.MemberSignupDTO;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialLoginDTO;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialSignupDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.model.Member;
import com.pknu.spatium_backend.repository.MemberRepository;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class MemberService {

    private final MemberRepository memberRepository;

    // 일반 회원가입 (POST /api/users)
    @Transactional
    public Map<String, Object> postUserSignup(MemberSignupDTO memDTO) {

        // ERD엔 동의여부 저장 컬럼이 없어서, 검증만 하고 DB엔 저장하지 않음
        if (!memDTO.isTermsAgreed() || !memDTO.isPrivacyAgreed()) {
            throw new ApiException(400, "TERMS_NOT_AGREED", "이용약관 및 개인정보처리방침에 동의해야 합니다.");
        }

        if (memberRepository.existsByMemEmail(memDTO.getEmail())) {
            throw new ApiException(409, "DUPLICATED_EMAIL", "이미 사용 중인 이메일입니다.");
        }

        Member member = Member.builder()
            .mem_id(UUID.randomUUID().toString())
            .mem_email(memDTO.getEmail())
            .mem_nick(memDTO.getNickname())
            .mem_pass(memDTO.getPassword())
            .mem_bir(memDTO.getBirthDate())
            .mem_sex(memDTO.getGender())
            .provider("LOCAL")
            .build();

        Member savedMember = memberRepository.save(member);

        return Map.of(
            "userId", savedMember.getMem_id(),
            "email", savedMember.getMem_email(),
            "nickname", savedMember.getMem_nick(),
            "profileImageUrl", ""
        );
    }

    // 소셜 로그인 (POST /api/auth/social-sessions)
    //  - ERD에 provider쪽 고유ID를 저장할 컬럼이 없어서, 이메일로 기존 가입 여부를 확인함
    public Map<String, Object> socialLogin(MemberSocialLoginDTO memDTO) {
        Member member = memberRepository
            .findByMemEmail(memDTO.getEmail())
            .orElseThrow(() -> new ApiException(404, "SOCIAL_USER_NOT_FOUND", "가입되지 않은 소셜 계정입니다. 회원가입이 필요합니다."));

        return Map.of(
            "userId", member.getMem_id(),
            "email", member.getMem_email(),
            "nickname", member.getMem_nick()
        );
    }

    // 소셜 회원가입 (POST /api/auth/social-users)
    @Transactional
    public Map<String, Object> socialSignup(MemberSocialSignupDTO memDTO) {

        // ERD엔 동의여부 저장 컬럼이 없어서, 검증만 하고 DB엔 저장하지 않음
        if (!memDTO.isTermsAgreed() || !memDTO.isPrivacyAgreed()) {
            throw new ApiException(400, "TERMS_NOT_AGREED", "이용약관 및 개인정보처리방침에 동의해야 합니다.");
        }

        // ERD엔 provider쪽 고유ID를 저장할 컬럼이 없어서, 이메일 기준으로 중복 확인
        if (memberRepository.existsByMemEmail(memDTO.getEmail())) {
            throw new ApiException(409, "SOCIAL_USER_ALREADY_EXISTS", "이미 가입된 계정입니다.");
        }

        Member member = Member.builder()
            .mem_id(memDTO.getProviderUserId())
            .mem_email(memDTO.getEmail())
            .mem_nick(memDTO.getNickname())
            .mem_bir(memDTO.getBirthDate())
            .mem_sex(memDTO.getGender())
            .provider(memDTO.getProvider())
            // mem_pass는 의도적으로 비워둠(null) -> 소셜 계정은 비밀번호가 없음
            .build();

        Member savedMember = memberRepository.save(member);

        return Map.of(
            "userId", savedMember.getMem_id(),
            "email", savedMember.getMem_email(),
            "nickname", savedMember.getMem_nick(),
            "profileImageUrl", ""
        );
    }

    public Map<String, Object> getMyInfo(String memId) {
        Member member = memberRepository.findById(memId)
            .orElseThrow(() -> new ApiException(404, "USER_NOT_FOUND", "회원을 찾을 수 없습니다."));

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
            .orElseThrow(() -> new ApiException(404, "USER_NOT_FOUND", "회원을 찾을 수 없습니다."));

        if (member.getMem_pass() == null || !member.getMem_pass().equals(password)) {
            throw new ApiException(400, "INVALID_PASSWORD", "비밀번호가 일치하지 않습니다.");
        }

        memberRepository.delete(member);
    }
}
