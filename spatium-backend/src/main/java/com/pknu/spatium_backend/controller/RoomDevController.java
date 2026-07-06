package com.pknu.spatium_backend.controller;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.service.RoomService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

// 개발(dev) 프로필 전용 테스트/디버그 API
//  - 운영 프로필에서는 이 컨트롤러 자체가 등록되지 않아 엔드포인트가 존재하지 않음(404)
//  - 정식 업로드 경로는 인증이 적용된 POST /api/projects/{projectId}/rooms 사용
@RestController
@RequiredArgsConstructor
@Slf4j
@Profile("dev")
public class RoomDevController {

    private final RoomService roomService;

    // iOS 스캐너 테스트 업로드 (회원 연결 없이 파일만 저장)
    @PostMapping(path = "/api/scans", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<String> post3dData(
            @RequestPart("metadata") String jsonDataFile,
            @RequestPart("file") MultipartFile usdzDataFile)
            throws IOException {

        log.info("metadata={}", jsonDataFile);
        log.info("usdz file name = {}", usdzDataFile.getOriginalFilename());
        log.info("usdz file size = {}", usdzDataFile.getSize());

        roomService.post3dData(jsonDataFile, usdzDataFile);

        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body("3D 파일 업로드 성공");
    }

    // 3D 에디터 테스트용 metadata 저장
    @PutMapping(
            path = "/api/test-three/metadata",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<?> putEditedMetadata(
            @RequestParam(required = false) String metadataUrl,
            @RequestBody String metadataJson) {

        if (metadataJson == null || metadataJson.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "message", "metadata JSON data is empty."
            ));
        }

        try {
            Path savedPath = roomService.saveEditedMetadata(metadataUrl, metadataJson);

            return ResponseEntity.ok(Map.of(
                    "message", "metadata JSON saved.",
                    "fileName", savedPath.getFileName().toString(),
                    "savedPath", savedPath.toString()
            ));
        } catch (IOException e) {
            log.error("Failed to save edited metadata JSON.", e);

            return ResponseEntity.internalServerError().body(Map.of(
                    "message", e.getMessage()
            ));
        }
    }

    // 로컬 metadata 파일 읽기 디버그용
    @GetMapping(path = "/test/read", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> testTransData() {
        Path jsonPath = Path.of(
                "C:\\pknu_2026_01\\22_final_project\\Spatium\\spatium-backend\\uploads\\models\\4550c4e3-a2e9-49cb-867b-5e5d5ca38732_metadata.json"
        );

        try {
            if (!Files.exists(jsonPath)) {
                return ResponseEntity.notFound().build();
            }

            String jsonData = Files.readString(jsonPath, StandardCharsets.UTF_8);

            return ResponseEntity
                    .ok()
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(jsonData);

        } catch (IOException e) {
            return ResponseEntity
                    .internalServerError()
                    .body("{\"message\":\"파일 읽기 실패\"}");
        }
    }
}
