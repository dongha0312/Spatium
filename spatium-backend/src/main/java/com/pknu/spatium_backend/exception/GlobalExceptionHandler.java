package com.pknu.spatium_backend.exception;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import com.pknu.spatium_backend.dto.ErrorResponseDTO;

import lombok.extern.slf4j.Slf4j;

@RestControllerAdvice
@Slf4j
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

    // @Valid 검증 실패 : 필드별 오류 메시지를 공통 포맷으로 반환
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponseDTO> handleMethodArgumentNotValid(MethodArgumentNotValidException e) {
        List<ErrorResponseDTO.FieldErrorDTO> fieldErrors = e.getBindingResult().getFieldErrors().stream()
                .map(error -> new ErrorResponseDTO.FieldErrorDTO(
                        error.getField(),
                        error.getDefaultMessage()))
                .toList();

        return ResponseEntity.badRequest().body(new ErrorResponseDTO(
                400,
                "INVALID_REQUEST",
                "요청 값이 올바르지 않습니다.",
                fieldErrors));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorResponseDTO> handleIllegalArgumentException(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(new ErrorResponseDTO(
                400,
                "INVALID_REQUEST",
                e.getMessage(),
                List.of()));
    }

    // 업로드 크기 제한 초과 (spring.servlet.multipart.max-file-size / max-request-size)
    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<ErrorResponseDTO> handleMaxUploadSizeExceeded(MaxUploadSizeExceededException e) {
        return ResponseEntity.status(413).body(new ErrorResponseDTO(
                413,
                "FILE_TOO_LARGE",
                "업로드 파일이 허용 크기를 초과했습니다.",
                List.of()));
    }

    // 존재하지 않는 경로 : catch-all(500)에 삼켜지지 않도록 404로 처리
    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<ErrorResponseDTO> handleNoResourceFound(NoResourceFoundException e) {
        return ResponseEntity.status(404).body(new ErrorResponseDTO(
                404,
                "NOT_FOUND",
                "요청한 리소스를 찾을 수 없습니다.",
                List.of()));
    }

    // 그 외 예상하지 못한 모든 예외 : 내부 정보(클래스명/메시지/스택트레이스)를
    // 응답에 노출하지 않고 고정 메시지로 반환. 상세 내용은 서버 로그에만 기록
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponseDTO> handleUnexpectedException(Exception e) {
        log.error("Unhandled exception", e);
        return ResponseEntity.internalServerError().body(new ErrorResponseDTO(
                500,
                "INTERNAL_SERVER_ERROR",
                "서버 내부 오류가 발생했습니다.",
                List.of()));
    }
}
