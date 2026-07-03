package com.pknu.spatium_backend.exception;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.pknu.spatium_backend.dto.ErrorResponseDTO;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ErrorResponseDTO> handleApiException(ApiException e) {
        return ResponseEntity
                .status(e.getStatusCode())
                .body(new ErrorResponseDTO(
                        e.getStatusCode(),
                        e.getCode(),
                        e.getMessage(),
                        List.of()));
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<ErrorResponseDTO> handleMissingRequestParameter(MissingServletRequestParameterException e) {
        return ResponseEntity.badRequest().body(new ErrorResponseDTO(
                400,
                "INVALID_REQUEST",
                "요청 값이 올바르지 않습니다.",
                List.of(new ErrorResponseDTO.FieldErrorDTO(e.getParameterName(), "필수 요청 값입니다."))));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorResponseDTO> handleIllegalArgumentException(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(new ErrorResponseDTO(
                400,
                "INVALID_REQUEST",
                e.getMessage(),
                List.of()));
    }
}
