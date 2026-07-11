package com.pknu.spatium_backend.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

public class ProjectDTO {

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    public static class ResponseProjectListDTO{
        private String projectId;

        private String projectName;

        private int roomCount;

        private int furnitureCount;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Data
    public static class ResponseProjectCreateDTO {
        private String projectId;

        private String projectName;
    }

}
