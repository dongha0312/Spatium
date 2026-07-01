package com.pknu.spatium_backend.controller;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.service.RoomService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@RestController
@RequiredArgsConstructor
@Slf4j
public class RoomController {

    private final RoomService roomService;

    @PostMapping(
        path = "/api/models",
        consumes = MediaType.MULTIPART_FORM_DATA_VALUE
    )
    public ResponseEntity<String> post3dData(
        @RequestPart("metadata") String jsonDataFile,
        @RequestPart("file") MultipartFile usdzDataFile
    ) 
    // 이게 왜 있는거지?
    throws IOException {

        log.info("===========================================================================================================");
        // log.info("metadata file name = {}", jsonDataFile.getOriginalFilename());
        // log.info("metadata content type = {}", jsonDataFile.getContentType());
        // JSON 데이터는 SpringBoot에서 들어올 때 String 타입으로 변환해버리는 것 같음.
        log.info(jsonDataFile);
        log.info("usdz file name = {}", usdzDataFile.getOriginalFilename());
        log.info("usdz file size = {}", usdzDataFile.getSize());
        log.info("===========================================================================================================");

        this.roomService.post3dData(jsonDataFile, usdzDataFile);

        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body("3D 파일 업로드 성공");
    }

        @GetMapping(
                path = "/test/read",
                produces = MediaType.APPLICATION_JSON_VALUE
        )
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