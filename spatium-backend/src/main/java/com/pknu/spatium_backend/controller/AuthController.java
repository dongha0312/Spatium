package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.dto.MemberDTO.LoginRequest;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.service.MemberService;
import com.pknu.spatium_backend.util.JwtUtil;

import lombok.RequiredArgsConstructor;

// auth 도메인 컨트롤러 (/api/auth/...)
//  - 로그인 (POST /api/auth/sessions)
@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/auth")
public class AuthController {

    private final MemberService memberService;

    private final JwtUtil jwtUtil;

    // 로그인 (POST /api/auth/sessions)
    @PostMapping(path = "/sessions")
    public ResponseEntity<?> postLogin(@RequestBody LoginRequest dto) {
        try {
            return ResponseEntity.status(200).body(Map.of(
                "statusCode", 200,
                "message", "로그인에 성공했습니다.",
                "data", memberService.login(dto)
            ));
        } catch (ApiException e) {
            return buildErrorResponse(e);
        }
    }

    // 로그아웃 (DELETE /api/auth/sessions/current)
    //  - stateless JWT 방식 : 서버에 세션 저장이 없으므로 토큰 검증만 하고 204 반환
    //    (실제 토큰 삭제는 클라이언트가 localStorage에서 지우는 것으로 처리)
    @DeleteMapping(path = "/sessions/current")
    public ResponseEntity<?> deleteLogout(
            @RequestHeader(value = "Authorization", required = false) String authorization) {

        // 헤더 없음 / "Bearer " 형식 아님 → 401
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            return buildErrorResponse(new ApiException(401, "UNAUTHORIZED", "유효하지 않은 토큰입니다."));
        }

        // 토큰 검증 (위조/만료 시 null)
        String memId = jwtUtil.validateAndGetMemId(authorization.substring(7).trim());
        if (memId == null) {
            return buildErrorResponse(new ApiException(401, "UNAUTHORIZED", "유효하지 않은 토큰입니다."));
        }

        // 204 No Content, body 없음
        return ResponseEntity.noContent().build();
    }

    // 명세서의 공통 에러 응답 형식 : {statusCode, code, message, errors}
    private ResponseEntity<?> buildErrorResponse(ApiException e) {
        return ResponseEntity.status(e.getStatusCode()).body(Map.of(
            "statusCode", e.getStatusCode(),
            "code", e.getCode(),
            "message", e.getMessage(),
            "errors", java.util.List.of()
        ));
    }
}
