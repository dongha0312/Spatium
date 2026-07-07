package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSignupDTO;
import com.pknu.spatium_backend.dto.MemberDTO.UserDeleteRequest;
import com.pknu.spatium_backend.dto.MemberDTO.UserUpdateRequest;
import com.pknu.spatium_backend.service.MemberService;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/users")
public class UserController {

    private final MemberService memberService;

    @PostMapping
    public ResponseEntity<?> postSignup(@Valid @RequestBody MemberSignupDTO memDTO) {
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

    // 회원 탈퇴 : 비밀번호(일반) 또는 소셜 idToken(소셜) 재확인 필수
    @DeleteMapping(path = "/me")
    public ResponseEntity<?> deleteUser(
            @AuthenticatedMemId String memId,
            @RequestBody(required = false) UserDeleteRequest dto) {

        String password = dto == null ? null : dto.getPassword();
        String idToken = dto == null ? null : dto.getIdToken();

        memberService.deleteUser(memId, password, idToken);
        return ResponseEntity.noContent().build();
    }
}
