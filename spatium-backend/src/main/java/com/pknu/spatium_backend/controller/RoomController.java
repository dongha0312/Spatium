package com.pknu.spatium_backend.controller;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.dto.PageResponseDTO;
import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomCreateDTO;
import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomSummaryDTO;
import com.pknu.spatium_backend.exception.ApiException;
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
            throws IOException {

        log.info("metadata={}", jsonDataFile);
        log.info("usdz file name = {}", usdzDataFile.getOriginalFilename());
        log.info("usdz file size = {}", usdzDataFile.getSize());

        roomService.post3dData(jsonDataFile, usdzDataFile);

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

    @GetMapping(path = "/api/projects/{projectId}/rooms")
    public ResponseEntity<?> getRooms(
            @AuthenticatedMemId String memId,
            @PathVariable String projectId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {

        List<ResponseRoomSummaryDTO> items = roomService.getRoomList(memId, projectId);

        PageResponseDTO<ResponseRoomSummaryDTO> data = new PageResponseDTO<>(
                items,
                page,
                size,
                items.size(),
                items.isEmpty() ? 0 : 1,
                false
        );

        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "룸 목록 조회에 성공했습니다.",
                "data", data
        ));
    }

    @PostMapping(path = "/api/projects/{projectId}/rooms", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> createRoom(
            @AuthenticatedMemId String memId,
            @PathVariable String projectId,
            @RequestParam String roomName,
            @RequestPart("metadata") MultipartFile metadata,
            @RequestPart("file") MultipartFile file) {

        try {
            ResponseRoomCreateDTO data = roomService.createRoom(
                    memId,
                    projectId,
                    roomName,
                    metadata,
                    file
            );

            return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                    "statusCode", 201,
                    "message", "룸이 생성되었습니다.",
                    "data", data
            ));
        } catch (IOException e) {
            throw new ApiException(
                    500,
                    "ROOM_SAVE_FAILED",
                    "룸 파일 저장에 실패했습니다."
            );
        }
    }

    @GetMapping(path = "/api/rooms/{roomId}")
    public ResponseEntity<?> getRoom(
            @AuthenticatedMemId String memId,
            @PathVariable String roomId) {

        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "룸 상세 조회에 성공했습니다.",
                "data", roomService.getRoom(memId, roomId)
        ));
    }

    @PostMapping(path = "/api/rooms/save", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> saveEditedRoom(
            @AuthenticatedMemId String memId,
            @RequestParam("projectId") String projectId,
            @RequestParam("roomId") String roomId,
            @RequestParam(value = "area", required = false) String area,
            @RequestPart("metadata") MultipartFile metadata) {

        roomService.saveEditedRoom(memId, projectId, roomId, area, metadata);

        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "수정된 룸 저장 완료",
                "data", Map.of()
        ));
    }

    @DeleteMapping(path = "/api/rooms")
    public ResponseEntity<?> deleteRoom(
            @AuthenticatedMemId String memId,
            @RequestBody Map<String, String> requestBody) {

        String projectId = requestBody == null ? null : requestBody.get("projectId");
        String roomId = requestBody == null ? null : requestBody.get("roomId");

        if (projectId == null || projectId.isBlank()) {
            throw new ApiException(
                    400,
                    "INVALID_PROJECT_ID",
                    "projectId가 필요합니다."
            );
        }

        if (roomId == null || roomId.isBlank()) {
            throw new ApiException(
                    400,
                    "INVALID_ROOM_ID",
                    "roomId가 필요합니다."
            );
        }

        try {
            roomService.deleteRoom(memId, projectId, roomId);

            return ResponseEntity.ok(Map.of(
                    "statusCode", 200,
                    "message", "룸 삭제에 성공했습니다.",
                    "data", roomId
            ));
        } catch (IllegalArgumentException e) {
            throw new ApiException(
                    404,
                    "ROOM_NOT_FOUND",
                    e.getMessage()
            );
        } catch (IllegalStateException e) {
            throw new ApiException(
                    500,
                    "ROOM_DELETE_FAILED",
                    e.getMessage()
            );
        }
    }
}
