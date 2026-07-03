package com.pknu.spatium_backend.controller;

import java.util.HashMap;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.dto.MemberDTO.MemberSignupDTO;
import com.pknu.spatium_backend.dto.ResponseDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.service.MemberService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/users")
public class UserController {

    private final MemberService memberService;

    // 일반 회원가입 (POST /api/users)
    @PostMapping
    public ResponseEntity<?> postSignup(@RequestBody MemberSignupDTO memDTO) {
        try {
            return ResponseEntity.status(201).body(Map.of(
                "statusCode", 201,
                "message", "회원가입이 완료되었습니다.",
                "data", memberService.postUserSignup(memDTO)
            ));
        } catch (ApiException e) {
            return buildErrorResponse(e);
        }
    }

    @PostMapping(path = "/me")
    // 테스트 할 수가 없어서 우선 RequestBody로 해 둠.
    // @RequestHeader(value = "Authorization", required = false) String authorization,
    // @RequestBody Map<String, Object> requestBody
    // 내 정보 조회
    public ResponseEntity<?> getMyInfo(@RequestBody Map<String, String> requestBody) {
        String memId = requestBody.get("memId");

        if (memId == null || memId.trim().isEmpty()) {
            Map<String, Object> errorBody = new HashMap<>();
            errorBody.put("statusCode", 400);
            errorBody.put("message", "회원 ID가 필요합니다.");
            errorBody.put("data", null);

            return ResponseEntity.badRequest().body(errorBody);
        }
        
        // ResponseDTO로 처리.
        try {
            return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "내 정보 조회에 성공했습니다.",
                "data", memberService.getMyInfo(memId.trim())
            ));
        } catch (ApiException e) {
            return buildErrorResponse(e);

        } catch (IllegalArgumentException e) {
            ResponseDTO<Object> errResponseDTO = new ResponseDTO<>();
            errResponseDTO.setStatusCode(404);
            errResponseDTO.setMessage(e.getMessage());
            errResponseDTO.setData(null);

            return ResponseEntity.status(404).body(errResponseDTO);
        }
    }

    // {"data":null,"message":"로그인이 필요합니다.","statusCode":401} ??
    // { "password": "Password123!", "confirmDelete": true }
    // 회원 탈퇴
    @DeleteMapping(path = "/me")
    public ResponseEntity<?> deleteUser(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestBody Map<String, Object> requestBody
    // @RequestBody Map<String, String> requestBody
    ) {
        // String memId = requestBody.get("memId");

        if (authorization == null || !authorization.startsWith("Bearer ")) {
            // if (memId == null || memId.trim().isEmpty()){
            Map<String, Object> errorBody = new HashMap<>();
            errorBody.put("statusCode", 401);
            errorBody.put("message", "로그인이 필요합니다.");
            errorBody.put("data", null);

            return ResponseEntity.status(401).body(errorBody);
        }

        String memId = authorization.substring(7).trim();
        String password = (String) requestBody.get("password");
        Boolean confirmDelete = (Boolean) requestBody.get("confirmDelete");

        if (memId.isEmpty()) {
            Map<String, Object> errorBody = new HashMap<>();
            errorBody.put("statusCode", 401);
            errorBody.put("message", "로그인이 필요합니다.");
            errorBody.put("data", null);

            return ResponseEntity.status(401).body(errorBody);
        }

        if (password == null || password.isBlank() || !Boolean.TRUE.equals(confirmDelete)) {
            Map<String, Object> errorBody = new HashMap<>();
            errorBody.put("statusCode", 400);
            errorBody.put("message", "비밀번호가 일치하지 않습니다.");
            errorBody.put("data", null);

            return ResponseEntity.badRequest().body(errorBody);
        }

        try {
            memberService.deleteUser(memId, password);

            Map<String, Object> responseBody = new HashMap<>();
            responseBody.put("statusCode", 204);
            responseBody.put("message", "회원 탈퇴가 완료되었습니다.");
            responseBody.put("data", null);

            return ResponseEntity.status(204).body(responseBody);

        } catch (ApiException e) {
            return buildErrorResponse(e);
        }
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
