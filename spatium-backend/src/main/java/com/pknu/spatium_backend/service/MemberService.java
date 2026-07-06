// MemberService.java
package com.pknu.spatium_backend.service;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.dto.MemberDTO.LoginRequest;
import com.pknu.spatium_backend.dto.MemberDTO.LoginResponse;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSignupDTO;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialLoginDTO;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSocialSignupDTO;
import com.pknu.spatium_backend.dto.MemberDTO.UserSummaryResponse;
import com.pknu.spatium_backend.auth.SocialIdTokenVerifier;
import com.pknu.spatium_backend.auth.SocialIdTokenVerifier.VerifiedSocialUser;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.model.Member;
import com.pknu.spatium_backend.repository.MemberRepository;
import com.pknu.spatium_backend.util.JwtUtil;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@RequiredArgsConstructor
@Slf4j
public class MemberService {

    private final MemberRepository memberRepository;

    private final JwtUtil jwtUtil;

    private final PasswordEncoder passwordEncoder;

    private final SocialIdTokenVerifier socialIdTokenVerifier;


    // 디폴트 이미지 위치.
    private static final String DEFAULT_PROFILE_IMAGE_URL = "http://localhost:8080/images/default-profile.png";

    // 일반 회원가입 (POST /api/users)
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
            // 평문 저장 금지 : BCrypt 해시로 저장
            .mem_pass(passwordEncoder.encode(memDTO.getPassword()))
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

    // 일반 로그인 (POST /api/auth/sessions)
    //  - stateless JWT 방식 : DB에 세션을 저장하지 않고 토큰만 발급함
    public LoginResponse login(LoginRequest dto) {
        // 입력한 이메일로 DB에서 회원 조회
        Member member = memberRepository.findByMemEmail(dto.getEmail())
            .orElseThrow(() -> new ApiException(401, "INVALID_CREDENTIALS", "이메일 또는 비밀번호가 일치하지 않습니다."));

        // 소셜 계정은 mem_pass가 null이므로 일반 로그인 불가
        // DB에 저장된 BCrypt 해시(mem_pass)와 입력한 비밀번호 비교
        if (member.getMem_pass() == null
                || dto.getPassword() == null
                || !passwordEncoder.matches(dto.getPassword(), member.getMem_pass())) {
            throw new ApiException(401, "INVALID_CREDENTIALS", "이메일 또는 비밀번호가 일치하지 않습니다.");
        }

        UserSummaryResponse user = new UserSummaryResponse(
            member.getMem_id(),
            member.getMem_email(),
            member.getMem_nick(),
            null
        );

        return new LoginResponse(
            jwtUtil.createAccessToken(member.getMem_id()),
            jwtUtil.createRefreshToken(member.getMem_id()),
            "Bearer",
            JwtUtil.ACCESS_TOKEN_EXPIRES_IN,
            user
        );
    }

    // 소셜 로그인 (POST /api/auth/social-sessions)
    //  - 클라이언트가 보낸 값을 신뢰하지 않고, ID Token을 서버가 직접 검증(서명/iss/aud)한다.
    //  - 검증된 sub(providerUserId)가 mem_id로 저장되어 있으므로 그것으로 회원을 찾는다.
    //  - 일반 로그인과 동일하게 JWT 토큰을 발급해서 LoginResponse 형태로 반환
    public LoginResponse socialLogin(MemberSocialLoginDTO memDTO) {
        VerifiedSocialUser verified =
            socialIdTokenVerifier.verify(memDTO.getProvider(), memDTO.getIdToken());

        // 검증된 sub와 DB의 mem_id(=providerUserId), provider가 모두 일치해야 로그인 허용
        Member member = memberRepository
            .findById(verified.providerUserId())
            .filter(found -> verified.provider().equalsIgnoreCase(found.getProvider()))
            .orElseThrow(() -> new ApiException(404, "SOCIAL_USER_NOT_FOUND", "가입되지 않은 소셜 계정입니다. 회원가입이 필요합니다."));

        UserSummaryResponse user = new UserSummaryResponse(
            member.getMem_id(),
            member.getMem_email(),
            member.getMem_nick(),
            null
        );

        return new LoginResponse(
            jwtUtil.createAccessToken(member.getMem_id()),
            jwtUtil.createRefreshToken(member.getMem_id()),
            "Bearer",
            JwtUtil.ACCESS_TOKEN_EXPIRES_IN,
            user
        );
    }

    // 소셜 회원가입 (POST /api/auth/social-users)
    //  - email/providerUserId는 클라이언트 입력이 아니라 검증된 ID Token에서 얻는다.
    @Transactional
    public Map<String, Object> socialSignup(MemberSocialSignupDTO memDTO) {

        // ERD엔 동의여부 저장 컬럼이 없어서, 검증만 하고 DB엔 저장하지 않음
        if (!memDTO.isTermsAgreed() || !memDTO.isPrivacyAgreed()) {
            throw new ApiException(400, "TERMS_NOT_AGREED", "이용약관 및 개인정보처리방침에 동의해야 합니다.");
        }

        VerifiedSocialUser verified =
            socialIdTokenVerifier.verify(memDTO.getProvider(), memDTO.getIdToken());

        if (verified.email() == null || verified.email().isBlank()) {
            throw new ApiException(400, "SOCIAL_EMAIL_REQUIRED", "소셜 계정에서 이메일을 확인할 수 없습니다.");
        }

        // 같은 소셜 계정(sub) 또는 같은 이메일로 이미 가입되어 있으면 중복 처리
        if (memberRepository.existsById(verified.providerUserId())
                || memberRepository.existsByMemEmail(verified.email())) {
            throw new ApiException(409, "SOCIAL_USER_ALREADY_EXISTS", "이미 가입된 계정입니다.");
        }

        Member member = Member.builder()
            .mem_id(verified.providerUserId())
            .mem_email(verified.email())
            .mem_nick(memDTO.getNickname())
            .mem_bir(memDTO.getBirthDate())
            .mem_sex(memDTO.getGender())
            .provider(verified.provider())
            // mem_pass는 의도적으로 비워둠(null) -> 소셜 계정은 비밀번호가 없음
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

        if (member.getMem_pass() == null
                || password == null
                || !passwordEncoder.matches(password, member.getMem_pass())) {
            throw new ApiException(400, "INVALID_PASSWORD", "비밀번호가 일치하지 않습니다.");
        }

        memberRepository.delete(member);
    }

    @Transactional
    public void deleteUser(String memId) {
        Member member = memberRepository.findById(memId)
            .orElseThrow(() -> new ApiException(404, "USER_NOT_FOUND", "회원을 찾을 수 없습니다."));

        memberRepository.delete(member);
    }
}
