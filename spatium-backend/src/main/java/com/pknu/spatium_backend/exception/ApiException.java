package com.pknu.spatium_backend.exception;

import lombok.Getter;

// 명세서의 공통 에러 응답 형식({statusCode, code, message, errors})을 맞추기 위한 예외
//  - statusCode : HTTP 상태코드
//  - code : "DUPLICATED_EMAIL" 같은 에러 코드 문자열
@Getter
public class ApiException extends RuntimeException {

    private final int statusCode;
    private final String code;

    public ApiException(int statusCode, String code, String message) {
        super(message);
        this.statusCode = statusCode;
        this.code = code;
    }
}
