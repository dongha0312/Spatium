package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomCreateDTO;
import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomSummaryDTO;
import com.pknu.spatium_backend.dto.RoomDTO.RoomSceneModelResponse;
import com.pknu.spatium_backend.dto.RoomDTO.RoomSceneResponse;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.model.Project;
import com.pknu.spatium_backend.model.Room;
import com.pknu.spatium_backend.repository.ProjectRepository;
import com.pknu.spatium_backend.repository.RoomRepository;
import com.pknu.spatium_backend.storage.FileStorage;
import com.pknu.spatium_backend.storage.FileStorageCleanup;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@RequiredArgsConstructor
@Slf4j
public class RoomService {

    public static final String ROOM_METADATA_FILE_NAME = "metadata.json";
    public static final String ROOM_SCENE_FILE_NAME = "scene.usdz";

    private final RoomRepository roomRepository;
    private final ProjectRepository projectRepository;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final FileStorage fileStorage;
    private final FileStorageCleanup fileStorageCleanup;
    private final FileValidationService fileValidationService;

    // 개발 프로필 전용 RoomDevController에서만 사용하는 기존 디버그 저장 기능이다.
    public void post3dData(String jsonDataFile, MultipartFile usdzDataFile) throws IOException {
        if (jsonDataFile == null || jsonDataFile.isBlank()) {
            throw new IOException("metadata JSON 데이터가 비어 있습니다.");
        }
        try {
            objectMapper.readTree(jsonDataFile);
        } catch (IOException e) {
            throw new IOException("metadata JSON 형식이 올바르지 않습니다.");
        }
        fileValidationService.validateUsdz(usdzDataFile);

        Path uploadDir = Paths.get(System.getProperty("user.dir"), "uploads", "models")
                .toAbsolutePath()
                .normalize();
        Files.createDirectories(uploadDir);

        String uploadId = UUID.randomUUID().toString();
        Path jsonPath = uploadDir.resolve(uploadId + "_metadata.json").normalize();
        String originalName = usdzDataFile.getOriginalFilename();
        String safeName = originalName == null || originalName.isBlank()
                ? "room-scan.usdz"
                : Path.of(originalName).getFileName().toString();
        Path usdzPath = uploadDir.resolve(uploadId + "_" + safeName).normalize();
        ensureInside(uploadDir, jsonPath);
        ensureInside(uploadDir, usdzPath);

        Files.writeString(jsonPath, jsonDataFile, StandardCharsets.UTF_8);
        Files.copy(usdzDataFile.getInputStream(), usdzPath, StandardCopyOption.REPLACE_EXISTING);
    }

    // 개발 프로필 전용 RoomDevController에서만 사용하는 기존 디버그 저장 기능이다.
    public Path saveEditedMetadata(String metadataUrl, String metadataJson) throws IOException {
        if (metadataJson == null || metadataJson.isBlank()) {
            throw new IOException("metadata JSON data is empty.");
        }
        try {
            objectMapper.readTree(metadataJson);
        } catch (IOException e) {
            throw new IOException("metadata JSON 형식이 올바르지 않습니다.");
        }

        Path uploadDir = Paths.get(System.getProperty("user.dir"), "uploads", "models")
                .toAbsolutePath()
                .normalize();
        Files.createDirectories(uploadDir);

        String sourceFileName = sanitizedJsonFileName(metadataUrl);
        String baseName = sourceFileName.replaceFirst("(?i)\\.json$", "");
        Path jsonPath = uploadDir.resolve(baseName + "_edited_" + UUID.randomUUID() + ".json").normalize();
        ensureInside(uploadDir, jsonPath);
        Files.writeString(jsonPath, metadataJson, StandardCharsets.UTF_8);
        log.info("Edited room metadata saved={}", jsonPath);
        return jsonPath;
    }

    @Transactional
    public ResponseRoomCreateDTO createRoom(
            String memId,
            String projectId,
            String roomName,
            MultipartFile metadata,
            MultipartFile file) throws IOException {
        Project project = getOwnedProject(memId, projectId);
        if (roomName == null || roomName.isBlank()) {
            throw new ApiException(400, "INVALID_ROOM_REQUEST", "룸 생성 요청 값이 올바르지 않습니다.");
        }

        fileValidationService.validateJson(metadata);
        fileValidationService.validateUsdz(file);

        String roomId = UUID.randomUUID().toString();
        String roomPrefix = buildRoomPath(project, roomId);
        List<String> objectKeys = roomObjectKeys(roomPrefix);

        try {
            fileStorage.store(metadataKey(roomPrefix), metadata.getInputStream());
            fileStorage.store(sceneKey(roomPrefix), file.getInputStream());
        } catch (IOException | RuntimeException e) {
            fileStorageCleanup.deleteNow(objectKeys);
            throw e;
        }
        fileStorageCleanup.deleteOnRollback(objectKeys);

        Room savedRoom = roomRepository.saveAndFlush(Room.builder()
                .room_id(roomId)
                .room_proj(projectId)
                .room_name(roomName.trim())
                .room_path(roomPrefix)
                .build());

        return new ResponseRoomCreateDTO(savedRoom.getRoom_id(), savedRoom.getRoom_name());
    }

    public List<ResponseRoomSummaryDTO> getRoomList(String memId, String projectId) {
        getOwnedProject(memId, projectId);
        return roomRepository.findByRoomProj(projectId).stream()
                .map(room -> {
                    LocalDateTime lastTouched = room.getRoom_modified() != null
                            ? room.getRoom_modified()
                            : room.getRoom_created();
                    return new ResponseRoomSummaryDTO(
                            room.getRoom_id(),
                            room.getRoom_name(),
                            room.getRoom_area(),
                            null,
                            lastTouched != null ? lastTouched.toString() : null);
                })
                .toList();
    }

    public Map<String, Object> getRoom(String memId, String roomId) {
        Room room = getOwnedRoom(memId, roomId);
        return Map.of("roomId", room.getRoom_id(), "roomName", room.getRoom_name());
    }

    public RoomSceneResponse getRoomScene(String memId, String roomId) {
        Room room = getOwnedRoom(memId, roomId);
        String roomPrefix = requireRoomPath(room);
        String metadataKey = metadataKey(roomPrefix);
        String sceneKey = sceneKey(roomPrefix);

        try {
            if (!fileStorage.exists(metadataKey)) {
                throw new ApiException(404, "ROOM_METADATA_NOT_FOUND", "룸 metadata 파일을 찾을 수 없습니다.");
            }
            if (!fileStorage.exists(sceneKey)) {
                throw new ApiException(404, "ROOM_MODEL_NOT_FOUND", "룸 model 파일을 찾을 수 없습니다.");
            }

            Object metadata;
            try (InputStream input = fileStorage.load(metadataKey).getInputStream()) {
                metadata = objectMapper.readValue(input, Object.class);
            }
            byte[] modelBytes;
            try (InputStream input = fileStorage.load(sceneKey).getInputStream()) {
                modelBytes = input.readAllBytes();
            }

            RoomSceneModelResponse model = new RoomSceneModelResponse(
                    ROOM_SCENE_FILE_NAME,
                    "model/vnd.usdz+zip",
                    Base64.getEncoder().encodeToString(modelBytes));
            return new RoomSceneResponse(room.getRoom_id(), room.getRoom_name(), metadata, model);
        } catch (ApiException e) {
            throw e;
        } catch (IllegalArgumentException e) {
            throw new ApiException(500, "ROOM_PATH_INVALID", "룸 저장 경로가 올바르지 않습니다.");
        } catch (IOException e) {
            throw new ApiException(500, "ROOM_SCENE_READ_FAILED", "룸 데이터를 불러오지 못했습니다.");
        }
    }

    @Transactional
    public void renameRoom(String memId, String roomId, String roomName) {
        if (roomName == null || roomName.isBlank()) {
            throw new ApiException(400, "INVALID_ROOM_NAME", "룸 이름이 올바르지 않습니다.");
        }
        Room room = getOwnedRoom(memId, roomId);
        room.setRoom_name(roomName.trim());
        roomRepository.save(room);
    }

    @Transactional
    public void saveEditedRoom(
            String memId,
            String projectId,
            String roomId,
            String area,
            MultipartFile metadata) {
        validateRequired(memId, "AUTH_REQUIRED", "로그인이 필요합니다.");
        validateRequired(projectId, "INVALID_PROJECT_ID", "projectId가 필요합니다.");
        validateRequired(roomId, "INVALID_ROOM_ID", "roomId가 필요합니다.");
        getOwnedProject(memId, projectId);

        Room room = getOwnedRoom(memId, roomId);
        if (!projectId.equals(room.getRoom_proj())) {
            throw new ApiException(404, "ROOM_NOT_FOUND", "룸을 찾을 수 없습니다.");
        }

        fileValidationService.validateJson(metadata);
        updateRoomArea(room, area);
        String roomPrefix = requireRoomPath(room);
        try {
            fileStorage.store(metadataKey(roomPrefix), metadata.getInputStream());
            roomRepository.saveAndFlush(room);
        } catch (IOException e) {
            throw new ApiException(500, "ROOM_SAVE_FAILED", "수정된 룸 저장에 실패했습니다.");
        }
    }

    @Transactional
    public void deleteRoom(String memId, String projectId, String roomId) {
        validateRequired(memId, "AUTH_REQUIRED", "로그인이 필요합니다.");
        validateRequired(projectId, "INVALID_PROJECT_ID", "projectId가 필요합니다.");
        validateRequired(roomId, "INVALID_ROOM_ID", "roomId가 필요합니다.");
        getOwnedProject(memId, projectId);

        Room room = getOwnedRoom(memId, roomId);
        if (!projectId.equals(room.getRoom_proj())) {
            throw new ApiException(404, "ROOM_NOT_FOUND", "삭제할 룸을 찾을 수 없습니다.");
        }

        List<String> objectKeys = roomObjectKeys(requireRoomPath(room));
        roomRepository.delete(room);
        roomRepository.flush();
        fileStorageCleanup.deleteAfterCommit(objectKeys);
    }

    private Project getOwnedProject(String memId, String projectId) {
        validateRequired(memId, "AUTH_REQUIRED", "로그인이 필요합니다.");
        validateRequired(projectId, "INVALID_PROJECT_ID", "projectId가 필요합니다.");

        Project project = projectRepository.findById(projectId)
                .orElseThrow(() -> new ApiException(404, "PROJECT_NOT_FOUND", "프로젝트를 찾을 수 없습니다."));
        if (!memId.equals(project.getProj_mem())) {
            throw new ApiException(403, "FORBIDDEN", "해당 프로젝트에 접근할 권한이 없습니다.");
        }
        return project;
    }

    private Room getOwnedRoom(String memId, String roomId) {
        validateRequired(memId, "AUTH_REQUIRED", "로그인이 필요합니다.");
        validateRequired(roomId, "INVALID_ROOM_ID", "roomId가 필요합니다.");
        Room room = roomRepository.findById(roomId)
                .orElseThrow(() -> new ApiException(404, "ROOM_NOT_FOUND", "룸을 찾을 수 없습니다."));
        getOwnedProject(memId, room.getRoom_proj());
        return room;
    }

    private String buildRoomPath(Project project, String roomId) {
        return String.join("/", "rooms", project.getProj_mem(), project.getProj_code(), roomId);
    }

    private String requireRoomPath(Room room) {
        if (room.getRoom_path() == null || room.getRoom_path().isBlank()) {
            throw new ApiException(500, "ROOM_PATH_NOT_FOUND", "룸 저장 경로가 없습니다.");
        }
        return room.getRoom_path();
    }

    public static List<String> roomObjectKeys(String roomPrefix) {
        return List.of(metadataKey(roomPrefix), sceneKey(roomPrefix));
    }

    public static String metadataKey(String roomPrefix) {
        return roomPrefix + "/" + ROOM_METADATA_FILE_NAME;
    }

    public static String sceneKey(String roomPrefix) {
        return roomPrefix + "/" + ROOM_SCENE_FILE_NAME;
    }

    private String sanitizedJsonFileName(String metadataUrl) {
        String value = metadataUrl == null ? "" : metadataUrl.trim();
        int queryIndex = value.indexOf('?');
        if (queryIndex >= 0) {
            value = value.substring(0, queryIndex);
        }
        value = value.replace("\\", "/");
        int slashIndex = value.lastIndexOf('/');
        String fileName = slashIndex >= 0 ? value.substring(slashIndex + 1) : value;
        fileName = fileName.replaceAll("[^a-zA-Z0-9._-]", "_");
        if (fileName.isBlank()) {
            fileName = "room-metadata.json";
        }
        if (!fileName.toLowerCase(Locale.ROOT).endsWith(".json")) {
            fileName += ".json";
        }
        return fileName;
    }

    private void updateRoomArea(Room room, String area) {
        if (area == null || area.isBlank()) {
            return;
        }
        double parsedArea;
        try {
            parsedArea = Double.parseDouble(area);
        } catch (NumberFormatException e) {
            throw new ApiException(400, "INVALID_ROOM_AREA", "room area 값이 올바르지 않습니다.");
        }
        if (!Double.isFinite(parsedArea) || parsedArea < 0) {
            throw new ApiException(400, "INVALID_ROOM_AREA", "room area 값이 올바르지 않습니다.");
        }
        room.setRoom_area(String.format(Locale.US, "%.2f", parsedArea));
    }

    private void ensureInside(Path parent, Path child) {
        if (!child.toAbsolutePath().normalize().startsWith(parent.toAbsolutePath().normalize())) {
            throw new ApiException(400, "INVALID_REQUEST", "저장 경로가 올바르지 않습니다.");
        }
    }

    private void validateRequired(String value, String errorCode, String message) {
        if (value == null || value.isBlank()) {
            throw new ApiException(400, errorCode, message);
        }
    }
}
