package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Stream;

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

        requireFileExtension(usdzDataFile, ".usdz", "3D 모델");

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

        ensureInside(uploadDir, jsonPath);
        ensureInside(uploadDir, usdzPath);

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

        ensureInside(uploadDir, jsonPath);

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
            throw new ApiException(
                    400,
                    "INVALID_ROOM_REQUEST",
                    "룸 생성 요청 값이 올바르지 않습니다."
            );
        }

        if (metadata == null || metadata.isEmpty() || file == null || file.isEmpty()) {
            throw new ApiException(
                    400,
                    "INVALID_ROOM_REQUEST",
                    "metadata와 file이 필요합니다."
            );
        }

        // 허용된 확장자만 업로드 가능
        requireFileExtension(metadata, ".json", "metadata");
        requireFileExtension(file, ".usdz", "3D 모델");

        String roomId = UUID.randomUUID().toString();

        Path saveDir = dataRoot()
                .resolve(project.getProj_mem())
                .resolve(project.getProj_code())
                .resolve(roomId)
                .toAbsolutePath()
                .normalize();

        Files.createDirectories(saveDir);

        Path metadataPath = saveDir
                .resolve(safeFileName(metadata.getOriginalFilename(), "metadata.json"))
                .normalize();

        Path filePath = saveDir
                .resolve(safeFileName(file.getOriginalFilename(), "room.usdz"))
                .normalize();

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

        return new ResponseRoomCreateDTO(
                savedRoom.getRoom_id(),
                savedRoom.getRoom_name()
        );
    }

    public List<ResponseRoomSummaryDTO> getRoomList(
            String memId,
            String projectId) {

        getOwnedProject(memId, projectId);

        return roomRepository.findByRoomProj(projectId).stream()
                .map(room -> new ResponseRoomSummaryDTO(
                        room.getRoom_id(),
                        room.getRoom_name(),
                        room.getRoom_area(),
                        null,
                        null
                ))
                .toList();
    }

    public Map<String, Object> getRoom(
            String memId,
            String roomId) {

        Room room = getOwnedRoom(memId, roomId);

        return Map.of(
                "roomId", room.getRoom_id(),
                "roomName", room.getRoom_name(),
                "roomPath", room.getRoom_path()
        );
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
            throw new ApiException(
                    404,
                    "ROOM_NOT_FOUND",
                    "룸을 찾을 수 없습니다."
            );
        }

        if (metadata == null || metadata.isEmpty()) {
            throw new ApiException(
                    400,
                    "INVALID_ROOM_REQUEST",
                    "metadata 파일이 필요합니다."
            );
        }

        requireFileExtension(metadata, ".json", "metadata");

        if (room.getRoom_path() == null || room.getRoom_path().isBlank()) {
            throw new ApiException(
                    500,
                    "ROOM_PATH_NOT_FOUND",
                    "룸 저장 경로가 없습니다."
            );
        }

        try {
            Path saveDir = Paths
                    .get(room.getRoom_path())
                    .toAbsolutePath()
                    .normalize();

            Files.createDirectories(saveDir);

            Path metadataPath = findExistingRoomMetadataPath(saveDir)
                    .toAbsolutePath()
                    .normalize();

            ensureInside(saveDir, metadataPath);

            Files.copy(
                    metadata.getInputStream(),
                    metadataPath,
                    StandardCopyOption.REPLACE_EXISTING
            );

            updateRoomArea(room, area);

        } catch (IOException e) {
            throw new ApiException(
                    500,
                    "ROOM_SAVE_FAILED",
                    "수정된 룸 저장에 실패했습니다."
            );
        }
    }

    @Transactional
    public void deleteRoom(
            String memId,
            String projectId,
            String roomId) {

        validateRequired(memId, "AUTH_REQUIRED", "로그인이 필요합니다.");
        validateRequired(projectId, "INVALID_PROJECT_ID", "projectId가 필요합니다.");
        validateRequired(roomId, "INVALID_ROOM_ID", "roomId가 필요합니다.");

        getOwnedProject(memId, projectId);

        Room room = getOwnedRoom(memId, roomId);

        if (!projectId.equals(room.getRoom_proj())) {
            throw new ApiException(
                    404,
                    "ROOM_NOT_FOUND",
                    "삭제할 룸을 찾을 수 없습니다."
            );
        }

        if (room.getRoom_path() == null || room.getRoom_path().isBlank()) {
            throw new ApiException(
                    500,
                    "ROOM_PATH_NOT_FOUND",
                    "룸 저장 경로가 없습니다."
            );
        }

        Path roomDir = Paths
                .get(room.getRoom_path())
                .toAbsolutePath()
                .normalize();

        roomRepository.delete(room);
        roomRepository.flush();

        deleteDirectory(roomDir);
    }

    private Project getOwnedProject(
            String memId,
            String projectId) {

        validateRequired(memId, "AUTH_REQUIRED", "로그인이 필요합니다.");
        validateRequired(projectId, "INVALID_PROJECT_ID", "projectId가 필요합니다.");

        Project project = projectRepository.findById(projectId)
                .orElseThrow(() -> new ApiException(
                        404,
                        "PROJECT_NOT_FOUND",
                        "프로젝트를 찾을 수 없습니다."
                ));

        if (!memId.equals(project.getProj_mem())) {
            throw new ApiException(
                    403,
                    "FORBIDDEN",
                    "해당 프로젝트에 접근할 권한이 없습니다."
            );
        }

        return project;
    }

    private Room getOwnedRoom(
            String memId,
            String roomId) {

        validateRequired(memId, "AUTH_REQUIRED", "로그인이 필요합니다.");
        validateRequired(roomId, "INVALID_ROOM_ID", "roomId가 필요합니다.");

        Room room = roomRepository.findById(roomId)
                .orElseThrow(() -> new ApiException(
                        404,
                        "ROOM_NOT_FOUND",
                        "룸을 찾을 수 없습니다."
                ));

        getOwnedProject(memId, room.getRoom_proj());

        return room;
    }

    private Path dataRoot() {
        return Paths
                .get(System.getProperty("user.dir"), "data")
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
        String fileName = slashIndex >= 0
                ? value.substring(slashIndex + 1)
                : value;

        fileName = fileName.replaceAll("[^a-zA-Z0-9._-]", "_");

        if (fileName.isBlank()) {
            fileName = "room-metadata.json";
        }

        if (!fileName.toLowerCase().endsWith(".json")) {
            fileName = fileName + ".json";
        }

        return fileName;
    }

    // 확장자 화이트리스트 검사 (파일명이 없으면 기본 파일명이 사용되므로 통과)
    private void requireFileExtension(
            MultipartFile file,
            String requiredExtension,
            String label) {

        String name = file.getOriginalFilename();
        if (name == null || name.isBlank()) {
            return;
        }

        if (!name.toLowerCase(Locale.ROOT).endsWith(requiredExtension)) {
            throw new ApiException(
                    400,
                    "INVALID_FILE_TYPE",
                    label + " 파일은 " + requiredExtension + " 형식만 업로드할 수 있습니다."
            );
        }
    }

    private String safeFileName(
            String originalFilename,
            String defaultFilename) {

        if (originalFilename == null || originalFilename.isBlank()) {
            return defaultFilename;
        }

        String fileName = Path.of(originalFilename)
                .getFileName()
                .toString();

        fileName = fileName.replaceAll("[^a-zA-Z0-9._-]", "_");

        return fileName.isBlank() ? defaultFilename : fileName;
    }

    private Path findExistingRoomMetadataPath(Path saveDir) throws IOException {
        try (Stream<Path> paths = Files.list(saveDir)) {
            List<Path> jsonFiles = paths
                    .filter(Files::isRegularFile)
                    .filter(path -> path.getFileName()
                            .toString()
                            .toLowerCase()
                            .endsWith(".json"))
                    .filter(path -> !"ai-edit-request.json".equalsIgnoreCase(
                            path.getFileName().toString()
                    ))
                    .sorted()
                    .toList();

            if (jsonFiles.isEmpty()) {
                return saveDir.resolve("metadata.json");
            }

            return jsonFiles.stream()
                    .filter(path -> !"metadata.json".equalsIgnoreCase(
                            path.getFileName().toString()
                    ))
                    .findFirst()
                    .orElse(jsonFiles.get(0));
        }
    }

    private void updateRoomArea(Room room, String area) {
        if (area == null || area.isBlank()) {
            return;
        }

        double parsedArea;
        try {
            parsedArea = Double.parseDouble(area);
        } catch (NumberFormatException e) {
            throw new ApiException(
                    400,
                    "INVALID_ROOM_AREA",
                    "room area 값이 올바르지 않습니다."
            );
        }

        if (!Double.isFinite(parsedArea) || parsedArea < 0) {
            throw new ApiException(
                    400,
                    "INVALID_ROOM_AREA",
                    "room area 값이 올바르지 않습니다."
            );
        }

        room.setRoom_area(String.format(Locale.US, "%.2f", parsedArea));
    }

    private void ensureInside(
            Path parent,
            Path child) {

        if (!child.toAbsolutePath()
                .normalize()
                .startsWith(parent.toAbsolutePath().normalize())) {

            throw new ApiException(
                    400,
                    "INVALID_REQUEST",
                    "저장 경로가 올바르지 않습니다."
            );
        }
    }

    private void deleteDirectory(Path targetDir) {
        Path dataRoot = dataRoot();

        Path normalizedTargetDir = targetDir
                .toAbsolutePath()
                .normalize();

        if (!normalizedTargetDir.startsWith(dataRoot)) {
            throw new ApiException(
                    400,
                    "INVALID_REQUEST",
                    "삭제할 수 없는 경로입니다."
            );
        }

        if (!Files.exists(normalizedTargetDir)) {
            log.info("삭제할 룸 폴더가 없습니다. path={}", normalizedTargetDir);
            return;
        }

        try (Stream<Path> paths = Files.walk(normalizedTargetDir)) {
            paths.sorted(Comparator.reverseOrder())
                    .forEach(path -> {
                        try {
                            Files.deleteIfExists(path);
                        } catch (IOException e) {
                            throw new IllegalStateException(
                                    "룸 폴더 삭제 중 오류가 발생했습니다.",
                                    e
                            );
                        }
                    });
        } catch (IOException e) {
            throw new IllegalStateException(
                    "룸 폴더 삭제 중 오류가 발생했습니다.",
                    e
            );
        }
    }

    private void validateRequired(
            String value,
            String errorCode,
            String message) {

        if (value == null || value.isBlank()) {
            throw new ApiException(
                    400,
                    errorCode,
                    message
            );
        }
    }
}
