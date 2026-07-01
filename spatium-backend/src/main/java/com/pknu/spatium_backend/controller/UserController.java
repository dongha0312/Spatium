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
@RequestMapping(path="/api/users")
public class UserController {

    @GetMapping(path="")
    public ResponseEntity<?> getMethodName(@RequestParam String param) {
        String qwer = "asdfasd";
        
        return ResponseEntity.ok("fqwera");
    }
    

}
