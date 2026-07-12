package com.pknu.spatium_backend.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

public class FurnitureDTO {

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Dimensions {
        private double x;
        private double y;
        private double z;
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
