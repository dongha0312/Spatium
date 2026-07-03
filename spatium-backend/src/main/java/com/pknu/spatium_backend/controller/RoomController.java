package com.pknu.spatium_backend.controller;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.dto.ResponseDTO;
import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomCreateDTO;
import com.pknu.spatium_backend.service.RoomService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@RestController
@RequiredArgsConstructor
@Slf4j
public class RoomController {

    private final RoomService roomService;

    @PostMapping(path = "/api/scans", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<String> post3dData(
            @RequestPart("metadata") String jsonDataFile,
            @RequestPart("file") MultipartFile usdzDataFile)
            // 이게 왜 있는거지?
            throws IOException {

        log.info(
                "===========================================================================================================");
        // log.info("metadata file name = {}", jsonDataFile.getOriginalFilename());
        // log.info("metadata content type = {}", jsonDataFile.getContentType());
        // JSON 데이터는 SpringBoot에서 들어올 때 String 타입으로 변환해버리는 것 같음.
        log.info(jsonDataFile);
        log.info("usdz file name = {}", usdzDataFile.getOriginalFilename());
        log.info("usdz file size = {}", usdzDataFile.getSize());
        log.info(
                "===========================================================================================================");

        this.roomService.post3dData(jsonDataFile, usdzDataFile);

        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body("3D 파일 업로드 성공");
    }

    @PutMapping(
            path = "/api/test-three/metadata",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<?> putEditedMetadata(
            @RequestParam(required = false) String metadataUrl,
            @RequestBody String metadataJson
    ) {

        if (metadataJson == null || metadataJson.isBlank()) {
            return ResponseEntity
                    .badRequest()
                    .body(Map.of("message", "metadata JSON data is empty."));
        }

        try {
            Path savedPath = roomService.saveEditedMetadata(
                    metadataUrl,
                    metadataJson
            );

            return ResponseEntity.ok(Map.of(
                    "message", "metadata JSON saved.",
                    "fileName", savedPath.getFileName().toString(),
                    "savedPath", savedPath.toString()
            ));
        } catch (IOException e) {
            log.error("Failed to save edited metadata JSON.", e);
            return ResponseEntity
                    .internalServerError()
                    .body(Map.of("message", e.getMessage()));
        }
    }

    @GetMapping(path = "/test/read", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> testTransData() {

        Path jsonPath = Path.of(
                "C:\\pknu_2026_01\\22_final_project\\Spatium\\spatium-backend\\uploads\\models\\4550c4e3-a2e9-49cb-867b-5e5d5ca38732_metadata.json");

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

    // 룸 생성하기
    @PostMapping(
            path = "/api/projects/{projectId}/rooms",
            consumes = MediaType.MULTIPART_FORM_DATA_VALUE
    )
    public ResponseEntity<?> createRoom(
            @PathVariable String projectId,
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestParam String roomName,
            @RequestPart("metadata") MultipartFile metadata,
            @RequestPart("file") MultipartFile file
    ) {
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            ResponseDTO<Object> responseDTO = new ResponseDTO<>();
            responseDTO.setStatusCode(401);
            responseDTO.setMessage("로그인이 필요합니다.");
            responseDTO.setData(null);

            return ResponseEntity.status(401).body(responseDTO);
        }

        String userId = authorization.substring(7).trim();

        if (userId.isEmpty()) {
            ResponseDTO<Object> responseDTO = new ResponseDTO<>();
            responseDTO.setStatusCode(401);
            responseDTO.setMessage("로그인이 필요합니다.");
            responseDTO.setData(null);

            return ResponseEntity.status(401).body(responseDTO);
        }

        try {
            ResponseRoomCreateDTO data = roomService.createRoom(
                    userId,
                    projectId,
                    roomName,
                    metadata,
                    file
            );

            ResponseDTO<ResponseRoomCreateDTO> responseDTO = new ResponseDTO<>();
            responseDTO.setStatusCode(201);
            responseDTO.setMessage("룸이 생성되었습니다.");
            responseDTO.setData(data);

            return ResponseEntity.status(201).body(responseDTO);
        } catch (IllegalArgumentException e) {
            ResponseDTO<Object> responseDTO = new ResponseDTO<>();
            responseDTO.setStatusCode(400);
            responseDTO.setMessage(e.getMessage());
            responseDTO.setData(null);

            return ResponseEntity.badRequest().body(responseDTO);
        } catch (IOException e) {
            ResponseDTO<Object> responseDTO = new ResponseDTO<>();
            responseDTO.setStatusCode(500);
            responseDTO.setMessage("룸 파일 저장에 실패했습니다.");
            responseDTO.setData(null);

            return ResponseEntity.internalServerError().body(responseDTO);
        }
    }
        

        // 룸 목록 조회
        @GetMapping(path="api/project/{projectId}/rooms")
        public String getMethodName(@RequestParam String projectId) {
            return new String();
        }
        


    }
