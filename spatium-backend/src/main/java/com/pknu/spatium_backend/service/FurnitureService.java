package com.pknu.spatium_backend.service;

import java.util.List;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.dto.FurnitureDTO.Dimensions;
import com.pknu.spatium_backend.dto.FurnitureDTO.ResponseCatalogItemDTO;
import com.pknu.spatium_backend.repository.FurnitureRepository;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
@RequiredArgsConstructor
public class FurnitureService {

    private final FurnitureRepository furnitureRepository;

    // 기본 제공 가구 카탈로그를 프론트가 기대하는 형태로 반환한다.
    public List<ResponseCatalogItemDTO> getCatalog() {
        return furnitureRepository.findDefaultCatalog().stream()
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
}
