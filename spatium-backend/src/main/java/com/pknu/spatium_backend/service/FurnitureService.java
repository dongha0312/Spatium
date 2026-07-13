package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.dto.FurnitureDTO.Dimensions;
import com.pknu.spatium_backend.dto.FurnitureDTO.RequestCreateDTO;
import com.pknu.spatium_backend.dto.FurnitureDTO.ResponseCatalogItemDTO;
import com.pknu.spatium_backend.dto.FurnitureDTO.ResponseCreateDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.model.Furniture;
import com.pknu.spatium_backend.repository.FurnitureRepository;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
@RequiredArgsConstructor
public class FurnitureService {

    private final FurnitureRepository furnitureRepository;

    public ResponseCreateDTO createUserFurniture(
            String memId,
            MultipartFile file,
            RequestCreateDTO metadata) throws IOException {
        validateGlb(file);

        Path uploadDir = userFurnitureDirectory();
        Files.createDirectories(uploadDir);

        String furnitureId = "usr_" + UUID.randomUUID().toString().replace("-", "");
        String fileName = furnitureId + ".glb";
        Path outputPath = uploadDir.resolve(fileName).normalize();
        if (!outputPath.startsWith(uploadDir)) {
            throw new ApiException(400, "INVALID_FILE_PATH", "가구 파일 경로가 올바르지 않습니다.");
        }

        try {
            Files.copy(file.getInputStream(), outputPath, StandardCopyOption.REPLACE_EXISTING);
            Dimensions dimensions = metadata.getDimensions();
            Furniture furniture = Furniture.builder()
                    .fur_code(furnitureId)
                    .fur_mem(memId)
                    .fur_name(metadata.getName().trim())
                    .fur_name_kr(metadata.getNameKr().trim())
                    .fur_category(metadata.getCategory().trim())
                    .fur_category_kr(metadata.getCategoryKr().trim())
                    .fur_width(Double.toString(dimensions.getX()))
                    .fur_height(Double.toString(dimensions.getY()))
                    .fur_depth(Double.toString(dimensions.getZ()))
                    .fur_path("/data/user_3d_models/" + fileName)
                    .fur_is_default("0")
                    .fur_is_active("1")
                    .build();
            furnitureRepository.saveAndFlush(furniture);
            return new ResponseCreateDTO(furnitureId, furniture.getFur_path());
        } catch (IOException | RuntimeException e) {
            Files.deleteIfExists(outputPath);
            throw e;
        }
    }

    // 로그인한 회원이 생성한 가구를 삭제한다 (fur_is_active='0' soft delete).
    // 이미 배치된 방이 GLB 경로를 계속 참조할 수 있으므로 파일은 지우지 않는다.
    public String deleteUserFurniture(String memId, String furCode) {
        Furniture furniture = furnitureRepository.findById(furCode)
                .filter(f -> "1".equals(f.getFur_is_active()))
                .orElseThrow(() -> new ApiException(404, "FURNITURE_NOT_FOUND", "가구를 찾을 수 없습니다."));

        if ("1".equals(furniture.getFur_is_default()) || !memId.equals(furniture.getFur_mem())) {
            throw new ApiException(403, "FORBIDDEN", "해당 가구를 삭제할 권한이 없습니다.");
        }

        furniture.setFur_is_active("0");
        furnitureRepository.save(furniture);
        return furCode;
    }

    // 기본 제공 가구 카탈로그를 프론트가 기대하는 형태로 반환한다.
    public List<ResponseCatalogItemDTO> getCatalog() {
        return toCatalogItems(furnitureRepository.findDefaultCatalog());
    }

    // 로그인한 회원이 생성한 사용자 가구 목록을 카탈로그와 동일한 형태로 반환한다.
    public List<ResponseCatalogItemDTO> getUserCatalog(String memId) {
        return toCatalogItems(furnitureRepository.findUserCatalog(memId));
    }

    private List<ResponseCatalogItemDTO> toCatalogItems(List<Furniture> furnitureList) {
        return furnitureList.stream()
                .map(f -> new ResponseCatalogItemDTO(
                        f.getFur_code(),
                        f.getFur_name_kr(),
                        f.getFur_category_kr(),
                        f.getFur_category(),
                        new Dimensions(
                                parseDimension(f.getFur_width()),
                                parseDimension(f.getFur_height()),
                                parseDimension(f.getFur_depth())),
                        f.getFur_path()))
                .toList();
    }

    // 치수는 VARCHAR2로 저장돼 있어 숫자로 변환한다. 값이 비정상이면 0으로 둔다.
    private double parseDimension(String value) {
        if (value == null || value.isBlank()) {
            return 0;
        }
        try {
            return Double.parseDouble(value.trim());
        } catch (NumberFormatException e) {
            log.warn("가구 치수 파싱 실패: {}", value);
            return 0;
        }
    }

    private Path userFurnitureDirectory() {
        Path cwd = Path.of(System.getProperty("user.dir")).toAbsolutePath().normalize();
        Path projectRoot = Files.isDirectory(cwd.resolve("spatium-frontend"))
                ? cwd
                : cwd.getParent();
        if (projectRoot == null || !Files.isDirectory(projectRoot.resolve("spatium-frontend"))) {
            throw new ApiException(
                    500,
                    "FURNITURE_STORAGE_NOT_FOUND",
                    "로컬 가구 저장 경로를 찾을 수 없습니다.");
        }
        return projectRoot
                .resolve("spatium-frontend")
                .resolve("public")
                .resolve("data")
                .resolve("user_3d_models")
                .toAbsolutePath()
                .normalize();
    }

    private void validateGlb(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new ApiException(400, "INVALID_FILE", "GLB 파일이 비어 있습니다.");
        }

        String originalName = file.getOriginalFilename();
        if (originalName != null
                && !originalName.isBlank()
                && !originalName.toLowerCase(Locale.ROOT).endsWith(".glb")) {
            throw new ApiException(400, "INVALID_FILE_TYPE", "가구 모델은 .glb 파일이어야 합니다.");
        }

        try (InputStream input = file.getInputStream()) {
            byte[] magic = input.readNBytes(4);
            boolean valid = magic.length == 4
                    && magic[0] == 'g'
                    && magic[1] == 'l'
                    && magic[2] == 'T'
                    && magic[3] == 'F';
            if (!valid) {
                throw new ApiException(400, "INVALID_FILE_TYPE", "올바른 GLB 2.0 파일이 아닙니다.");
            }
        } catch (IOException e) {
            throw new ApiException(400, "INVALID_FILE", "GLB 파일을 읽을 수 없습니다.");
        }
    }
}
