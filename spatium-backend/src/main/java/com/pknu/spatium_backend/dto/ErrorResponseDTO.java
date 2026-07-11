package com.pknu.spatium_backend.dto;

import java.util.List;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ErrorResponseDTO {

    private int statusCode;

    private String code;

    private String message;

    private List<FieldErrorDTO> errors;

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class FieldErrorDTO {
        private String field;

        private String message;
    }
}