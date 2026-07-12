package com.pknu.spatium_backend.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

public class FurnitureDTO {

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Dimensions {
        @Positive(message = "가로 길이는 0보다 커야 합니다.")
        private double x;
        @Positive(message = "높이는 0보다 커야 합니다.")
        private double y;
        @Positive(message = "깊이는 0보다 커야 합니다.")
        private double z;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RequestCreateDTO {
        @NotBlank(message = "한글 가구 이름이 필요합니다.")
        private String nameKr;

        @NotBlank(message = "가구 이름이 필요합니다.")
        private String name;

        @NotBlank(message = "카테고리가 필요합니다.")
        private String category;

        @NotBlank(message = "한글 카테고리가 필요합니다.")
        private String categoryKr;

        @Valid
        @NotNull(message = "가구 치수가 필요합니다.")
        private Dimensions dimensions;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ResponseCreateDTO {
        private String id;

        private String modelUrl;
    }

    // 프론트 furniture_catalog.json 항목과 동일한 형태.
    // (id / name / group / category / dimensions / modelUrl)
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ResponseCatalogItemDTO {
        private String id;

        private String name;

        private String group;

        private String category;

        private Dimensions dimensions;

        private String modelUrl;
    }
}
