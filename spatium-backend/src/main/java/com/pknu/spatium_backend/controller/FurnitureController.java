package com.pknu.spatium_backend.controller;

import java.io.IOException;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.dto.FurnitureDTO.RequestCreateDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.service.FurnitureService;

import jakarta.validation.Valid;
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

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> createUserFurniture(
            @AuthenticatedMemId String memId,
            @RequestPart("file") MultipartFile file,
            @Valid @RequestPart("metadata") RequestCreateDTO metadata) {
        try {
            return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                    "statusCode", 201,
                    "message", "가구가 목록에 추가되었습니다.",
                    "data", furnitureService.createUserFurniture(memId, file, metadata)));
        } catch (IOException e) {
            throw new ApiException(
                    500,
                    "FURNITURE_SAVE_FAILED",
                    "가구 모델 파일 저장에 실패했습니다.");
        }
    }
}
