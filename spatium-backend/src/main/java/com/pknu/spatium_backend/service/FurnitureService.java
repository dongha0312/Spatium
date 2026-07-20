package com.pknu.spatium_backend.service;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.List;
import java.util.UUID;

import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.dto.FurnitureDTO.Dimensions;
import com.pknu.spatium_backend.dto.FurnitureDTO.RequestCreateDTO;
import com.pknu.spatium_backend.dto.FurnitureDTO.ResponseCatalogItemDTO;
import com.pknu.spatium_backend.dto.FurnitureDTO.ResponseCreateDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.model.Furniture;
import com.pknu.spatium_backend.repository.FurnitureRepository;
import com.pknu.spatium_backend.storage.FileStorage;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
@RequiredArgsConstructor
public class FurnitureService {

    private final FurnitureRepository furnitureRepository;
    private final FileStorage fileStorage;
    private final FileValidationService fileValidationService;

    public ResponseCreateDTO createUserFurniture(
            String memId,
            MultipartFile file,
            RequestCreateDTO metadata) throws IOException {
        fileValidationService.validateGlb(file);

        String furnitureId = "usr_" + UUID.randomUUID().toString().replace("-", "");
        String objectKey = "furniture/" + memId + "/" + furnitureId + ".glb";
        fileStorage.store(objectKey, file.getInputStream());

        try {
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
                    .fur_path(objectKey)
                    .fur_is_default("0")
                    .fur_is_active("1")
                    .build();
            furnitureRepository.saveAndFlush(furniture);
            return new ResponseCreateDTO(furnitureId, userModelUrl(furnitureId));
        } catch (RuntimeException e) {
            try {
                fileStorage.delete(objectKey);
            } catch (IOException cleanupError) {
                e.addSuppressed(cleanupError);
                log.warn("Furniture file rollback failed. key={}", objectKey, cleanupError);
            }
            throw e;
        }
    }

    // 기존 룸 배치 metadata가 GLB 경로를 참조할 수 있어 soft delete 시 파일은 유지한다.
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

    public List<ResponseCatalogItemDTO> getCatalog() {
        return toCatalogItems(furnitureRepository.findDefaultCatalog());
    }

    public List<ResponseCatalogItemDTO> getUserCatalog(String memId) {
        return toCatalogItems(furnitureRepository.findUserCatalog(memId));
    }

    /**
     * Inactive user furniture remains downloadable by its owner because a saved
     * room can still reference it after catalog soft deletion.
     */
    public FurnitureModelResource getUserFurnitureModel(String memId, String furCode) {
        Furniture furniture = furnitureRepository.findById(furCode)
                .filter(f -> "0".equals(f.getFur_is_default()))
                .filter(f -> memId.equals(f.getFur_mem()))
                .orElseThrow(() -> new ApiException(404, "FURNITURE_NOT_FOUND", "가구를 찾을 수 없습니다."));

        try {
            Resource resource = fileStorage.load(furniture.getFur_path());
            return new FurnitureModelResource(resource, resource.contentLength(), furniture.getFur_code() + ".glb");
        } catch (FileNotFoundException | IllegalArgumentException e) {
            throw new ApiException(404, "FURNITURE_MODEL_NOT_FOUND", "가구 모델 파일을 찾을 수 없습니다.");
        } catch (IOException e) {
            throw new ApiException(500, "FURNITURE_MODEL_READ_FAILED", "가구 모델 파일을 읽을 수 없습니다.");
        }
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
                        "1".equals(f.getFur_is_default()) ? f.getFur_path() : userModelUrl(f.getFur_code())))
                .toList();
    }

    private String userModelUrl(String furnitureId) {
        return "/api/furniture/" + furnitureId + "/model";
    }

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

    public record FurnitureModelResource(Resource resource, long contentLength, String fileName) {
    }
}
