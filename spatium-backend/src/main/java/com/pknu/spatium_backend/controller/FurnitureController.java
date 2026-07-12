package com.pknu.spatium_backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.service.FurnitureService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/furniture")
public class FurnitureController {

    private final FurnitureService furnitureService;

    // 기본 제공 가구 카탈로그 조회 (기존 furniture_catalog.json 대체)
    @GetMapping
    public ResponseEntity<?> getCatalog() {
        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "가구 카탈로그 조회에 성공했습니다.",
                "data", furnitureService.getCatalog()));
    }
}
