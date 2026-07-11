package com.pknu.spatium_backend.controller;

import java.io.IOException;
import java.util.List;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.dto.PageResponseDTO;
import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomCreateDTO;
import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomSummaryDTO;
import com.pknu.spatium_backend.dto.RoomDTO.RoomSceneResponse;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.service.RoomService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@RestController
@RequiredArgsConstructor
@Slf4j
public class RoomController {

    private final RoomService roomService;

    // 테스트/디버그용 엔드포인트(/api/scans, /api/test-three/metadata, /test/read)는
    // RoomDevController(@Profile("dev"))로 이동 : 운영 프로필에서는 존재하지 않음

    // 룸 목록 조회
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

    // 새 룸 만들기
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

    // 룸 불러오기
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
    
    // 저장된 내 룸 모델링 데이터 불러오기
    @GetMapping(path = "/api/rooms/{roomId}/scene")
    public ResponseEntity<?> getRoomScene(
            @AuthenticatedMemId String memId,
            @PathVariable String roomId) {

        RoomSceneResponse data = roomService.getRoomScene(memId, roomId);

        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "룸 3D 데이터 조회에 성공했습니다.",
                "data", data
        ));
    }

    // 룸 이름 변경
    @PatchMapping(path = "/api/rooms/{roomId}")
    public ResponseEntity<?> renameRoom(
            @AuthenticatedMemId String memId,
            @PathVariable String roomId,
            @RequestBody Map<String, String> requestBody) {

        String roomName = requestBody == null ? null : requestBody.get("roomName");
        if (roomName == null || roomName.trim().isEmpty()) {
            throw new ApiException(400, "INVALID_ROOM_NAME", "룸 이름이 올바르지 않습니다.");
        }

        String trimmedName = roomName.trim();
        roomService.renameRoom(memId, roomId, trimmedName);

        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "룸 이름이 수정되었습니다.",
                "data", Map.of("roomId", roomId, "roomName", trimmedName)
        ));
    }

    // 수정된 룸 저장하기
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

    // 내 룸 삭제하기
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
