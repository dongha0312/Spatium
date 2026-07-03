package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomCreateDTO;
import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomSummaryDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.model.Project;
import com.pknu.spatium_backend.model.Room;
import com.pknu.spatium_backend.repository.ProjectRepository;
import com.pknu.spatium_backend.repository.RoomRepository;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@RequiredArgsConstructor
@Slf4j
public class RoomService {

    private final RoomRepository roomRepository;
    private final ProjectRepository projectRepository;

    public void post3dData(
            String jsonDataFile,
            MultipartFile usdzDataFile) throws IOException {
        if (jsonDataFile == null || jsonDataFile.isBlank()) {
            throw new IOException("metadata JSON 데이터가 비어 있습니다.");
        }

        if (usdzDataFile == null || usdzDataFile.isEmpty()) {
            throw new IOException("USDZ 파일이 비어 있습니다.");
        }

        Path uploadDir = Paths
                .get(System.getProperty("user.dir"), "uploads", "models")
                .toAbsolutePath()
                .normalize();

        Files.createDirectories(uploadDir);

        String uploadId = UUID.randomUUID().toString();
        String jsonFileName = uploadId + "_metadata.json";
        String usdzOriginalName = usdzDataFile.getOriginalFilename();
        if (usdzOriginalName == null || usdzOriginalName.isBlank()) {
            usdzOriginalName = "room-scan.usdz";
        }

        String usdzFileName = uploadId + "_" + Path.of(usdzOriginalName)
                .getFileName()
                .toString();

        Path jsonPath = uploadDir.resolve(jsonFileName).normalize();
        Path usdzPath = uploadDir.resolve(usdzFileName).normalize();

        Files.writeString(jsonPath, jsonDataFile, StandardCharsets.UTF_8);
        Files.copy(usdzDataFile.getInputStream(), usdzPath, StandardCopyOption.REPLACE_EXISTING);
    }

    public Path saveEditedMetadata(
            String metadataUrl,
            String metadataJson) throws IOException {
        if (metadataJson == null || metadataJson.isBlank()) {
            throw new IOException("metadata JSON data is empty.");
        }

        Path uploadDir = Paths
                .get(System.getProperty("user.dir"), "uploads", "models")
                .toAbsolutePath()
                .normalize();

        Files.createDirectories(uploadDir);

        String sourceFileName = sanitizedJsonFileName(metadataUrl);
        String baseName = sourceFileName.replaceFirst("(?i)\\.json$", "");
        String jsonFileName = baseName + "_edited_" + UUID.randomUUID() + ".json";
        Path jsonPath = uploadDir.resolve(jsonFileName).normalize();

        if (!jsonPath.startsWith(uploadDir)) {
            throw new IOException("Invalid metadata save path.");
        }

        Files.writeString(jsonPath, metadataJson, StandardCharsets.UTF_8);
        log.info("Edited room metadata saved = {}", jsonPath);
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

        if (metadata == null || metadata.isEmpty() || file == null || file.isEmpty()) {
            throw new ApiException(400, "INVALID_ROOM_REQUEST", "metadata와 file이 필요합니다.");
        }

        String roomId = UUID.randomUUID().toString();
        // 실제 룸 파일 저장 구조: data/{memId}/{projectId}/{roomId}
        // memId와 projectId는 요청값이 아니라 소유권 검증이 끝난 Project 엔티티 값을 사용한다.
        Path saveDir = dataRoot()
                .resolve(project.getProj_mem())
                .resolve(project.getProj_code())
                .resolve(roomId)
                .toAbsolutePath()
                .normalize();

        Files.createDirectories(saveDir);

        Path metadataPath = saveDir.resolve(safeFileName(metadata.getOriginalFilename(), "metadata.json")).normalize();
        Path filePath = saveDir.resolve(safeFileName(file.getOriginalFilename(), "room.usdz")).normalize();

        ensureInside(saveDir, metadataPath);
        ensureInside(saveDir, filePath);

        Files.copy(metadata.getInputStream(), metadataPath, StandardCopyOption.REPLACE_EXISTING);
        Files.copy(file.getInputStream(), filePath, StandardCopyOption.REPLACE_EXISTING);

        Room room = Room.builder()
                .room_id(roomId)
                .room_proj(projectId)
                .room_name(roomName)
                .room_path(saveDir.toString())
                .build();

        Room savedRoom = roomRepository.save(room);
        return new ResponseRoomCreateDTO(savedRoom.getRoom_id(), savedRoom.getRoom_name());
    }

    public List<ResponseRoomSummaryDTO> getRoomList(String memId, String projectId) {
        getOwnedProject(memId, projectId);

        return roomRepository.findByRoomProj(projectId).stream()
                .map(room -> new ResponseRoomSummaryDTO(
                        room.getRoom_id(),
                        room.getRoom_name(),
                        room.getRoom_area(),
                        null,
                        null))
                .toList();
    }

    public Map<String, Object> getRoom(String memId, String roomId) {
        Room room = getOwnedRoom(memId, roomId);
        return Map.of("roomPath", room.getRoom_path());
    }

    public void saveEditedRoom(
            String memId,
            String projectId,
            String roomId,
            MultipartFile metadata) {
        // projectId와 roomId가 모두 현재 사용자 소유인지 확인한 뒤 기존 room_path에 덮어쓴다.
        getOwnedProject(memId, projectId);
        Room room = getOwnedRoom(memId, roomId);

        if (!projectId.equals(room.getRoom_proj())) {
            throw new ApiException(404, "ROOM_NOT_FOUND", "룸을 찾을 수 없습니다.");
        }

        if (metadata == null || metadata.isEmpty()) {
            throw new ApiException(400, "INVALID_ROOM_REQUEST", "metadata 파일이 필요합니다.");
        }

        try {
            // 룸 생성 시 DB에 저장해 둔 폴더 경로를 재사용한다.
            Path saveDir = Paths.get(room.getRoom_path()).toAbsolutePath().normalize();
            Files.createDirectories(saveDir);

            String metadataFileName = safeFileName(metadata.getOriginalFilename(), "metadata.json");
            if (!metadataFileName.toLowerCase().endsWith(".json")) {
                metadataFileName = "metadata.json";
            }

            Path metadataPath = saveDir.resolve(metadataFileName).toAbsolutePath().normalize();
            ensureInside(saveDir, metadataPath);

            Files.copy(metadata.getInputStream(), metadataPath, StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            throw new ApiException(500, "ROOM_SAVE_FAILED", "수정된 룸 저장에 실패했습니다.");
        }
    }

    private Project getOwnedProject(String memId, String projectId) {
        Project project = projectRepository.findById(projectId)
                .orElseThrow(() -> new ApiException(404, "PROJECT_NOT_FOUND", "프로젝트를 찾을 수 없습니다."));

        // JWT에서 검증된 memId와 프로젝트 소유자(proj_mem)가 다르면 접근을 막는다.
        if (!memId.equals(project.getProj_mem())) {
            throw new ApiException(403, "FORBIDDEN", "해당 프로젝트에 접근할 권한이 없습니다.");
        }

        return project;
    }

    private Room getOwnedRoom(String memId, String roomId) {
        Room room = roomRepository.findById(roomId)
                .orElseThrow(() -> new ApiException(404, "ROOM_NOT_FOUND", "룸을 찾을 수 없습니다."));

        // Room은 프로젝트에 속하므로 room_proj를 통해 프로젝트 소유권까지 함께 검증한다.
        getOwnedProject(memId, room.getRoom_proj());
        return room;
    }

    private Path dataRoot() {
        // 현재는 서버 실행 위치 기준의 data 폴더를 루트로 사용한다.
        return Paths.get(System.getProperty("user.dir"), "data")
                .toAbsolutePath()
                .normalize();
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
        if (!fileName.toLowerCase().endsWith(".json")) {
            fileName = fileName + ".json";
        }
        return fileName;
    }

    private String safeFileName(String originalFilename, String defaultFilename) {
        if (originalFilename == null || originalFilename.isBlank()) {
            return defaultFilename;
        }

        String fileName = Path.of(originalFilename).getFileName().toString();
        fileName = fileName.replaceAll("[^a-zA-Z0-9._-]", "_");
        return fileName.isBlank() ? defaultFilename : fileName;
    }

    private void ensureInside(Path parent, Path child) {
        // 업로드 파일명이 ../ 등을 포함해도 지정된 룸 폴더 밖으로 저장되지 않게 방어한다.
        if (!child.toAbsolutePath().normalize().startsWith(parent.toAbsolutePath().normalize())) {
            throw new ApiException(400, "INVALID_REQUEST", "저장 경로가 올바르지 않습니다.");
        }
    }
}
