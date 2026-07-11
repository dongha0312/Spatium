package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.auth.SignupRateLimiter;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSignupDTO;
import com.pknu.spatium_backend.dto.MemberDTO.UserUpdateRequest;
import com.pknu.spatium_backend.service.MemberService;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/users")
public class UserController {

    private final MemberService memberService;
    private final SignupRateLimiter signupRateLimiter;

    @PostMapping
    public ResponseEntity<?> postSignup(
            @Valid @RequestBody MemberSignupDTO memDTO,
            HttpServletRequest request) {

        // 이메일 열거/대량 가입 방지 : 같은 IP의 가입 시도 횟수 제한 (초과 시 429)
        //  (리버스 프록시 뒤에 배포하면 X-Forwarded-For 처리 필요 - server.forward-headers-strategy)
        signupRateLimiter.checkAndRecord(request.getRemoteAddr());

        return ResponseEntity.status(201).body(Map.of(
                "statusCode", 201,
                "message", "회원가입이 완료되었습니다.",
                "data", memberService.postUserSignup(memDTO)));
    }

    @GetMapping(path = "/me")
    public ResponseEntity<?> getMyInfo(@AuthenticatedMemId String memId) {
        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "내 정보 조회에 성공했습니다.",
                "data", memberService.getMyInfo(memId)));
    }

    // 내 정보 수정 : 전달된 필드만 수정 (닉네임/생년월일/비밀번호)
    @PatchMapping(path = "/me")
    public ResponseEntity<?> updateMyInfo(
            @AuthenticatedMemId String memId,
            @Valid @RequestBody(required = false) UserUpdateRequest dto) {

        String nickname = dto == null ? null : dto.getNickname();
        String birthDate = dto == null ? null : dto.getBirthDate();
        String password = dto == null ? null : dto.getPassword();

        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "내 정보가 수정되었습니다.",
                "data", memberService.updateMyInfo(memId, nickname, birthDate, password)));
    }

    // 프로필 사진 변경 : multipart/form-data 로 image 파일을 받아 저장
    @PutMapping(path = "/me/avatar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> updateAvatar(
            @AuthenticatedMemId String memId,
            @RequestPart("image") MultipartFile image) {

        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "프로필 사진이 변경되었습니다.",
                "data", memberService.updateAvatar(memId, image)));
    }

    // 프로필 사진 삭제 : 저장된 이미지를 지우고 기본(이니셜) 상태로 되돌림
    @DeleteMapping(path = "/me/avatar")
    public ResponseEntity<?> deleteAvatar(@AuthenticatedMemId String memId) {
        memberService.deleteAvatar(memId);
        return ResponseEntity.noContent().build();
    }

    // 회원 탈퇴 : 추가 본인 확인 없이 바로 처리
    @DeleteMapping(path = "/me")
    public ResponseEntity<?> deleteUser(@AuthenticatedMemId String memId) {
        memberService.deleteUser(memId);
        return ResponseEntity.noContent().build();
    }
}
