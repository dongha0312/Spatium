package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.dto.member.MemberSignupDTO;
import com.pknu.spatium_backend.service.MemberService;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;



@RestController
@RequiredArgsConstructor
@RequestMapping(path="/api/auth")
public class MemberController {

    private final MemberService memberService;

    @PostMapping(path = "/signup")
    public ResponseEntity<?> postUserSignup(@RequestBody MemberSignupDTO memDTO) {
        try {
            return ResponseEntity.status(201).body(Map.of(
                "statusCode", 201,
                "message", "회원가입이 완료되었습니다.",
                "data", memberService.postUserSignup(memDTO)
            ));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(409).body(Map.of(
                "statusCode", 409,
                "message", e.getMessage()
            ));
        }
    }
 
    
}
