package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.UUID;

import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.dto.RoomDTO.ResponseRoomCreateDTO;
import com.pknu.spatium_backend.model.Room;
import com.pknu.spatium_backend.repository.RoomRepository;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@RequiredArgsConstructor
@Slf4j
public class RoomService {

    private final RoomRepository roomRepository;

    public void post3dData(
            String jsonDataFile,
            MultipartFile usdzDataFile) throws IOException {

        if (jsonDataFile == null || jsonDataFile.isBlank()) {
            throw new IOException("metadata JSON 데이터가 비어 있습니다.");
        }

        if (usdzDataFile == null || usdzDataFile.isEmpty()) {
            throw new IOException("USDZ 파일이 비어 있습니다.");
        }

        // Path에 저장하는 경로.
        // userID, projId, roomId를 이용해서 특정 위치에 데이터를 저장하면 됨.
        Path uploadDir = Paths
                .get(System.getProperty("user.dir"), "uploads", "models")
                .toAbsolutePath()
                .normalize();

        Files.createDirectories(uploadDir);

        // 파일 명 앞에 UUID를 적어놓아서 중복 방지.
        String uploadId = UUID.randomUUID().toString();

        String jsonFileName = uploadId + "_metadata.json";

        String usdzOriginalName = usdzDataFile.getOriginalFilename();
        if (usdzOriginalName == null || usdzOriginalName.isBlank()) {
            usdzOriginalName = "room-scan.usdz";
        }

        String usdzFileName = uploadId + "_" + Path.of(usdzOriginalName)
                .getFileName()
                .toString();

        // 무슨 코드?
        Path jsonPath = uploadDir.resolve(jsonFileName).normalize();
        Path usdzPath = uploadDir.resolve(usdzFileName).normalize();

        log.info("업로드 폴더 = {}", uploadDir);
        log.info("JSON 저장 경로 = {}", jsonPath);
        log.info("USDZ 저장 경로 = {}", usdzPath);

        Files.writeString(
                jsonPath,
                jsonDataFile,
                StandardCharsets.UTF_8);

        Files.copy(
                usdzDataFile.getInputStream(),
                usdzPath,
                StandardCopyOption.REPLACE_EXISTING);
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
        // 수정된 ROOM JSON 파일 저장 이름
        String jsonFileName = baseName + "_edited_" + UUID.randomUUID() + ".json";
        Path jsonPath = uploadDir.resolve(jsonFileName).normalize();

        if (!jsonPath.startsWith(uploadDir)) {
            throw new IOException("Invalid metadata save path.");
        }

        Files.writeString(
                jsonPath,
                metadataJson,
                StandardCharsets.UTF_8);

        log.info("Edited room metadata saved = {}", jsonPath);

        return jsonPath;
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

    @Transactional
    public ResponseRoomCreateDTO createRoom(
            String userId,
            String projectId,
            String roomName,
            MultipartFile metadata,
            MultipartFile file) throws IOException {
        if (roomName == null || roomName.isBlank()) {
            throw new IllegalArgumentException("룸 이름이 필요합니다.");
        }

        if (metadata == null || metadata.isEmpty()) {
            throw new IllegalArgumentException("metadata 파일이 필요합니다.");
        }

        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("usdz 파일이 필요합니다.");
        }

        String roomId = UUID.randomUUID().toString();

        Path saveDir = Paths
                .get(System.getProperty("user.dir"), "data")
                .resolve(userId)
                .resolve(projectId)
                .resolve(roomId)
                .toAbsolutePath()
                .normalize();

        Files.createDirectories(saveDir);

        String metadataFileName = safeFileName(metadata.getOriginalFilename(), "metadata.json");
        String usdzFileName = safeFileName(file.getOriginalFilename(), "room.usdz");

        Path metadataPath = saveDir.resolve(metadataFileName).normalize();
        Path filePath = saveDir.resolve(usdzFileName).normalize();

        Files.copy(metadata.getInputStream(), metadataPath, StandardCopyOption.REPLACE_EXISTING);
        Files.copy(file.getInputStream(), filePath, StandardCopyOption.REPLACE_EXISTING);

        Room room = Room.builder()
                .room_id(roomId)
                .room_proj(projectId)
                .room_name(roomName)
                .room_path(saveDir.toString())
                .build();

        Room savedRoom = roomRepository.save(room);

        return new ResponseRoomCreateDTO(
                savedRoom.getRoom_id(),
                savedRoom.getRoom_name());
    }

    private String safeFileName(String originalFilename, String defaultFilename) {
        if (originalFilename == null || originalFilename.isBlank()) {
            return defaultFilename;
        }

        String fileName = Path.of(originalFilename).getFileName().toString();
        fileName = fileName.replaceAll("[^a-zA-Z0-9._-]", "_");

        return fileName.isBlank() ? defaultFilename : fileName;
    }

    // 수정된 룸 저장
    public ResponseEntity<String> saveEditedRoom(
            String authorizationHeader,
            String projectId,
            String roomId,
            MultipartFile metadata) {
        if (authorizationHeader == null || !authorizationHeader.startsWith("Bearer ")) {
            return ResponseEntity.status(401).body("로그인이 필요합니다.");
        }

        String userId = authorizationHeader.substring(7).trim();

        if (userId.isEmpty()) {
            return ResponseEntity.status(401).body("로그인이 필요합니다.");
        }

        if (projectId == null || projectId.isBlank()) {
            return ResponseEntity.badRequest().body("projectId가 필요합니다.");
        }

        if (roomId == null || roomId.isBlank()) {
            return ResponseEntity.badRequest().body("roomId가 필요합니다.");
        }

        if (metadata == null || metadata.isEmpty()) {
            return ResponseEntity.badRequest().body("metadata 파일이 필요합니다.");
        }

        try {
            Path dataDir = Paths
                    .get(System.getProperty("user.dir"), "data")
                    .toAbsolutePath()
                    .normalize();

            Path saveDir = dataDir
                    .resolve(userId)
                    .resolve(projectId)
                    .resolve(roomId)
                    .toAbsolutePath()
                    .normalize();

            if (!saveDir.startsWith(dataDir)) {
                return ResponseEntity.badRequest().body("잘못된 저장 경로입니다.");
            }

            Files.createDirectories(saveDir);

            String metadataFileName = safeFileName(metadata.getOriginalFilename(), "metadata.json");

            if (!metadataFileName.toLowerCase().endsWith(".json")) {
                metadataFileName = "metadata.json";
            }

            Path metadataPath = saveDir
                    .resolve(metadataFileName)
                    .toAbsolutePath()
                    .normalize();

            if (!metadataPath.startsWith(saveDir)) {
                return ResponseEntity.badRequest().body("잘못된 파일명입니다.");
            }

            Files.copy(
                    metadata.getInputStream(),
                    metadataPath,
                    StandardCopyOption.REPLACE_EXISTING);

            return ResponseEntity.ok("수정된 룸이 저장되었습니다.");

        } catch (IOException e) {
            return ResponseEntity
                    .internalServerError()
                    .body("수정된 룸 저장에 실패했습니다.");
        }
    }
}
