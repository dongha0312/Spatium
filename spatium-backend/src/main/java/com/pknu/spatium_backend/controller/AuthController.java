package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.dto.MemberDTO.LoginRequest;
import com.pknu.spatium_backend.service.MemberService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/auth")
public class AuthController {

    private final MemberService memberService;

    @PostMapping(path = "/sessions")
    public ResponseEntity<?> postLogin(@RequestBody LoginRequest dto) {
        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "로그인에 성공했습니다.",
                "data", memberService.login(dto)));
    }

    @DeleteMapping(path = "/sessions/current")
    public ResponseEntity<?> deleteLogout(@AuthenticatedMemId String memId) {
        return ResponseEntity.noContent().build();
    }
}
