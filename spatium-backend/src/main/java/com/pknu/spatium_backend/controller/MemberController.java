package com.pknu.spatium_backend.controller;

import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.service.MemberService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
public class MemberController {

    private final MemberService memberService;

}
