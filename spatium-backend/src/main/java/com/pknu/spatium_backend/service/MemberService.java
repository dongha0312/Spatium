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
import com.pknu.spatium_backend.auth.LoginAttemptLimiter;
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

    private final RefreshTokenService refreshTokenService;

    private final LoginAttemptLimiter loginAttemptLimiter;


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
    //  - brute-force 방어 : 같은 (이메일+IP) 조합이 5회 연속 실패하면 5분간 잠금(429)
    public LoginResponse login(LoginRequest dto, String clientIp) {
        String attemptKey = normalizeEmail(dto.getEmail()) + "|" + clientIp;
        loginAttemptLimiter.checkNotBlocked(attemptKey);

        // 입력한 이메일로 DB에서 회원 조회
        Member member = memberRepository.findByMemEmail(dto.getEmail())
            .orElseThrow(() -> {
                loginAttemptLimiter.recordFailure(attemptKey);
                return new ApiException(401, "INVALID_CREDENTIALS", "이메일 또는 비밀번호가 일치하지 않습니다.");
            });

        // 소셜 계정은 mem_pass가 null이므로 일반 로그인 불가
        // DB에 저장된 BCrypt 해시(mem_pass)와 입력한 비밀번호 비교
        if (member.getMem_pass() == null
                || dto.getPassword() == null
                || !passwordEncoder.matches(dto.getPassword(), member.getMem_pass())) {
            loginAttemptLimiter.recordFailure(attemptKey);
            throw new ApiException(401, "INVALID_CREDENTIALS", "이메일 또는 비밀번호가 일치하지 않습니다.");
        }

        loginAttemptLimiter.recordSuccess(attemptKey);
        return issueLoginResponse(member);
    }

    private String normalizeEmail(String email) {
        return email == null ? "" : email.trim().toLowerCase();
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

        return issueLoginResponse(member);
    }

    // 토큰 재발급 (POST /api/auth/token)
    //  - refreshToken(type=refresh)의 서명/만료 검증 + 서버 저장소 대조 후
    //    기존 토큰을 폐기하고 새 access/refresh 쌍을 발급한다 (rotation)
    public LoginResponse reissueTokens(String refreshToken) {
        if (refreshToken == null || refreshToken.isBlank()) {
            throw new ApiException(400, "INVALID_REQUEST", "refreshToken이 필요합니다.");
        }

        // 1) JWT 자체 검증 : 서명/만료/type=refresh
        String memId = jwtUtil.validateRefreshTokenAndGetMemId(refreshToken);
        if (memId == null) {
            throw new ApiException(401, "INVALID_REFRESH_TOKEN", "유효하지 않은 refresh token입니다.");
        }

        // 2) 실존 회원 확인
        Member member = memberRepository.findById(memId)
            .orElseThrow(() -> new ApiException(401, "INVALID_REFRESH_TOKEN", "유효하지 않은 refresh token입니다."));

        // 3) 서버 저장소 대조 : 폐기되지 않은 저장 토큰인지 확인 후 폐기(rotation)
        refreshTokenService.validateAndRevokeForRotation(memId, refreshToken);

        // 4) 새 토큰 쌍 발급/저장
        return issueLoginResponse(member);
    }

    // 로그아웃 (DELETE /api/auth/sessions/current)
    //  - 해당 회원의 refreshToken을 서버에서 전부 폐기 -> 재발급 불가
    public void logout(String memId) {
        refreshTokenService.revokeAll(memId);
    }

    // 토큰 쌍 발급 + refreshToken 서버 저장 + 로그인 응답 생성 (공통)
    private LoginResponse issueLoginResponse(Member member) {
        UserSummaryResponse user = new UserSummaryResponse(
            member.getMem_id(),
            member.getMem_email(),
            member.getMem_nick(),
            null
        );

        String accessToken = jwtUtil.createAccessToken(member.getMem_id());
        String refreshToken = jwtUtil.createRefreshToken(member.getMem_id());

        // 발급된 refreshToken을 서버에 저장해야 로그아웃/재발급 시 무효화 가능
        refreshTokenService.issue(member.getMem_id(), refreshToken);

        return new LoginResponse(
            accessToken,
            refreshToken,
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

    // 내 정보 수정 (PATCH /api/users/me)
    //  - 전달된 필드만 수정하고, null이면 기존 값을 유지한다.
    //  - password는 값이 있을 때만 새 비밀번호로 변경 (소셜 회원은 비밀번호가 없으므로 무시)
    @Transactional
    public Map<String, Object> updateMyInfo(String memId, String nickname, String birthDate, String password) {
        Member member = memberRepository.findById(memId)
            .orElseThrow(() -> new ApiException(404, "USER_NOT_FOUND", "회원을 찾을 수 없습니다."));

        if (nickname != null && !nickname.trim().isEmpty()) {
            member.setMem_nick(nickname.trim());
        }

        if (birthDate != null && !birthDate.trim().isEmpty()) {
            member.setMem_bir(birthDate.trim());
        }

        // 일반(LOCAL) 회원만 비밀번호 변경 가능 (소셜 회원은 mem_pass가 null)
        if (password != null && !password.trim().isEmpty()) {
            if (member.getMem_pass() == null) {
                throw new ApiException(400, "PASSWORD_NOT_ALLOWED", "소셜 회원은 비밀번호를 변경할 수 없습니다.");
            }
            member.setMem_pass(passwordEncoder.encode(password));
        }

        memberRepository.save(member);

        return getMyInfo(memId);
    }

    // 회원 탈퇴 (DELETE /api/users/me)
    //  - accessToken 탈취만으로 계정을 삭제할 수 없도록 본인 재확인을 요구한다.
    //  - 일반(LOCAL) 회원 : 현재 비밀번호 확인
    //  - 소셜 회원(비밀번호 없음) : 소셜 로그인을 다시 수행해 받은 idToken 검증
    @Transactional
    public void deleteUser(String memId, String password, String idToken) {
        Member member = memberRepository.findById(memId)
            .orElseThrow(() -> new ApiException(404, "USER_NOT_FOUND", "회원을 찾을 수 없습니다."));

        if (member.getMem_pass() != null) {
            // 일반(LOCAL) 회원 : 비밀번호 재확인
            if (password == null || !passwordEncoder.matches(password, member.getMem_pass())) {
                throw new ApiException(400, "INVALID_PASSWORD", "비밀번호가 일치하지 않습니다.");
            }
        } else {
            // 소셜 회원 : 소셜 ID Token 재검증으로 본인 확인
            if (idToken == null || idToken.isBlank()) {
                throw new ApiException(400, "SOCIAL_VERIFICATION_REQUIRED",
                    "소셜 계정 본인 확인(idToken)이 필요합니다.");
            }

            VerifiedSocialUser verified =
                socialIdTokenVerifier.verify(member.getProvider(), idToken);

            // 다른 소셜 계정의 토큰으로 탈퇴하는 것을 방지 (sub == mem_id 확인)
            if (!verified.providerUserId().equals(member.getMem_id())) {
                throw new ApiException(400, "SOCIAL_VERIFICATION_FAILED",
                    "소셜 계정 본인 확인에 실패했습니다.");
            }
        }

        refreshTokenService.deleteAll(memId);
        memberRepository.delete(member);
    }
}
