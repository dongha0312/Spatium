package com.pknu.spatium_backend.controller;

import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.service.CommunityService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
public class CommunityController {

    private final CommunityService commnunityService;

}
