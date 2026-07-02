package com.pknu.spatium_backend.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Data

// 공통 응답 DTO
public class ResponseDTO<T> {
    
    private int statusCode;

    private String message;

    private T data;
}

