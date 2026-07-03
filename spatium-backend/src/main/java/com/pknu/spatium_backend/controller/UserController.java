package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.dto.MemberDTO.MemberSignupDTO;
import com.pknu.spatium_backend.service.MemberService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/users")
public class UserController {

    private final MemberService memberService;

    @PostMapping
    public ResponseEntity<?> postSignup(@RequestBody MemberSignupDTO memDTO) {
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

    @DeleteMapping(path = "/me")
    public ResponseEntity<?> deleteUser(@AuthenticatedMemId String memId) {
        memberService.deleteUser(memId);
        return ResponseEntity.noContent().build();
    }
}
