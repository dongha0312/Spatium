package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.dto.MemberDTO.MemberSignupDTO;
import com.pknu.spatium_backend.service.MemberService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

import com.pknu.spatium_backend.dto.MemberDTO;
@RestController
@RequiredArgsConstructor
@RequestMapping(path="/api")
@Slf4j

public class MemberController {

    private final MemberService memberService;

    // 일반 회원가입 기능
    @PostMapping(path = "/users")
    public ResponseEntity<?> postUserSignup(@RequestBody MemberSignupDTO memDTO) {
        try {
            // 추후 ResponseDTO로 리팩토링
            log.info("controller");
            return ResponseEntity.status(201).body(Map.of(
                "statusCode", 201,
                "message", "회원가입이 완료되었습니다.",
                "data", memberService.postUserSignup(memDTO)
            ));
            // 추후 ResponseDTO로 리팩토링
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(409).body(Map.of(
                "statusCode", 409,
                "message", e.getMessage()
            ));
        }
    }
 
    
}
