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
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Stream;

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

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@RequiredArgsConstructor
@Slf4j
public class RoomService {

    private final RoomRepository roomRepository;
    private final ProjectRepository projectRepository;
    private final ObjectMapper objectMapper = new ObjectMapper();

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
        requireUsdzContent(usdzDataFile);

        // metadata 문자열도 실제 JSON인지 검증 후 저장
        try {
            objectMapper.readTree(jsonDataFile);
        } catch (IOException e) {
            throw new IOException("metadata JSON 형식이 올바르지 않습니다.");
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

        // 실제 JSON인지 검증 후 저장 (임의 콘텐츠 저장 방지)
        try {
            objectMapper.readTree(metadataJson);
        } catch (IOException e) {
            throw new IOException("metadata JSON 형식이 올바르지 않습니다.");
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

        // 허용된 확장자만 업로드 가능 + 실제 내용(JSON/zip 매직바이트)까지 검증
        requireFileExtension(metadata, ".json", "metadata");
        requireFileExtension(file, ".usdz", "3D 모델");
        requireJsonContent(metadata);
        requireUsdzContent(file);

        String roomId = UUID.randomUUID().toString();

        // DB에는 실제 PC 경로가 아니라 data 폴더 기준 상대 경로만 저장한다.
        // 예: rooms/{memberId}/{projectId}/{roomId}
        String roomPath = buildRoomPath(project, roomId);

        // 파일 저장/조회가 필요할 때만 상대 경로를 실제 서버 경로로 변환한다.
        // 예: {backend 실행 위치}/data/rooms/{memberId}/{projectId}/{roomId}
        Path saveDir = resolveRoomDirectory(roomPath);

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
                .room_path(roomPath)
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
                .map(room -> {
                    // 수정된 적 없는 룸(구버전 데이터 등)은 생성일로 대체한다.
                    LocalDateTime lastTouched = room.getRoom_modified() != null
                            ? room.getRoom_modified()
                            : room.getRoom_created();
                    return new ResponseRoomSummaryDTO(
                            room.getRoom_id(),
                            room.getRoom_name(),
                            room.getRoom_area(),
                            null,
                            lastTouched != null ? lastTouched.toString() : null
                    );
                })
                .toList();
    }

    public Map<String, Object> getRoom(
            String memId,
            String roomId) {

        Room room = getOwnedRoom(memId, roomId);

        // 서버 저장 경로(roomPath)는 내부 구현 정보라 응답에 포함하지 않는다.
        return Map.of(
                "roomId", room.getRoom_id(),
                "roomName", room.getRoom_name()
        );
    }

    public RoomSceneResponse getRoomScene(
            String memId,
            String roomId) {

        Room room = getOwnedRoom(memId, roomId);

        if (room.getRoom_path() == null || room.getRoom_path().isBlank()) {
            throw new ApiException(
                    500,
                    "ROOM_PATH_NOT_FOUND",
                    "룸 저장 경로가 없습니다."
            );
        }

        try {
            Path saveDir = resolveRoomDirectory(room.getRoom_path());

            Path metadataPath = findExistingRoomMetadataPath(saveDir)
                    .toAbsolutePath()
                    .normalize();
            Path modelPath = findExistingRoomModelPath(saveDir)
                    .toAbsolutePath()
                    .normalize();

            ensureInside(saveDir, metadataPath);
            ensureInside(saveDir, modelPath);

            if (!Files.exists(metadataPath) || !Files.isRegularFile(metadataPath)) {
                throw new ApiException(
                        404,
                        "ROOM_METADATA_NOT_FOUND",
                        "룸 metadata 파일을 찾을 수 없습니다."
                );
            }

            if (!Files.exists(modelPath) || !Files.isRegularFile(modelPath)) {
                throw new ApiException(
                        404,
                        "ROOM_MODEL_NOT_FOUND",
                        "룸 model 파일을 찾을 수 없습니다."
                );
            }

            Object metadata = objectMapper.readValue(metadataPath.toFile(), Object.class);
            byte[] modelBytes = Files.readAllBytes(modelPath);

            RoomSceneModelResponse model = new RoomSceneModelResponse(
                    modelPath.getFileName().toString(),
                    "model/vnd.usdz+zip",
                    Base64.getEncoder().encodeToString(modelBytes)
            );

            return new RoomSceneResponse(
                    room.getRoom_id(),
                    room.getRoom_name(),
                    metadata,
                    model
            );
        } catch (ApiException e) {
            throw e;
        } catch (IOException e) {
            throw new ApiException(
                    500,
                    "ROOM_SCENE_READ_FAILED",
                    "룸 데이터를 불러오지 못했습니다."
            );
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
        requireJsonContent(metadata);

        if (room.getRoom_path() == null || room.getRoom_path().isBlank()) {
            throw new ApiException(
                    500,
                    "ROOM_PATH_NOT_FOUND",
                    "룸 저장 경로가 없습니다."
            );
        }

        try {
            Path saveDir = resolveRoomDirectory(room.getRoom_path());

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

        Path roomDir = resolveRoomDirectory(room.getRoom_path());

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

    // DB에는 개발자 PC마다 달라지는 절대경로 대신 저장소 루트 기준 상대 key만 보관한다.
    private String buildRoomPath(Project project, String roomId) {
        return String.join(
                "/",
                project.getProj_mem(),
                project.getProj_code(),
                roomId
        );
    }

    // 파일을 읽고 쓸 때만 상대 key를 실제 서버 파일 경로로 변환한다.
    private Path resolveRoomDirectory(String roomPath) {
        Path root = dataRoot();
        Path roomDir = root.resolve(roomPath)
                .toAbsolutePath()
                .normalize();

        ensureInside(root, roomDir);

        return roomDir;
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
    //  - 확장자는 위조 가능하므로 이 검사만으로는 부족하다.
    //    실제 내용 검증은 requireJsonContent/requireUsdzContent가 수행한다.
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

    // metadata 파일이 실제로 파싱 가능한 JSON인지 내용까지 검증
    //  - 확장자만 .json으로 위조한 임의 파일이 저장/서빙되는 것을 차단
    //  - 파일명이 없어서 확장자 검사를 통과한 경우도 여기서 걸러진다.
    private void requireJsonContent(MultipartFile file) {
        try (InputStream in = file.getInputStream()) {
            objectMapper.readTree(in);
        } catch (IOException e) {
            throw new ApiException(
                    400,
                    "INVALID_FILE_TYPE",
                    "metadata 파일이 올바른 JSON 형식이 아닙니다."
            );
        }
    }

    // USDZ는 zip 컨테이너 형식 : 파일 시작이 zip 매직 바이트(PK\x03\x04)인지 검증
    //  - 확장자만 .usdz로 위조한 임의 파일이 저장/서빙되는 것을 차단
    private void requireUsdzContent(MultipartFile file) {
        try (InputStream in = file.getInputStream()) {
            byte[] header = in.readNBytes(4);
            boolean zipMagic = header.length == 4
                    && header[0] == 'P'
                    && header[1] == 'K'
                    && header[2] == 3
                    && header[3] == 4;

            if (!zipMagic) {
                throw new ApiException(
                        400,
                        "INVALID_FILE_TYPE",
                        "3D 모델 파일이 올바른 USDZ 형식이 아닙니다."
                );
            }
        } catch (IOException e) {
            throw new ApiException(
                    400,
                    "INVALID_FILE_TYPE",
                    "3D 모델 파일을 읽을 수 없습니다."
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

    private Path findExistingRoomModelPath(Path saveDir) throws IOException {
        try (Stream<Path> paths = Files.list(saveDir)) {
            return paths
                    .filter(Files::isRegularFile)
                    .filter(path -> path.getFileName()
                            .toString()
                            .toLowerCase(Locale.ROOT)
                            .endsWith(".usdz"))
                    .sorted()
                    .findFirst()
                    .orElse(saveDir.resolve("room.usdz"));
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
