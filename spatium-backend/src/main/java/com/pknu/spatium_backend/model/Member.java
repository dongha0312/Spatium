package com.pknu.spatium_backend.model;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.ToString;

// ERD(최종본) 기준으로 맞춤 : mem_id는 VARCHAR2(36) 문자열 PK, provider 컬럼 하나만 존재
@Entity
@Table(name="Member")
@Getter
@Setter

@NoArgsConstructor
@AllArgsConstructor

@Builder

@ToString
public class Member {

    @Id
    private String mem_id;

    private String mem_nick;

    private String mem_email;

    // 소셜 가입 회원은 비밀번호가 없을 수 있음 (nullable)
    private String mem_pass;

    private String mem_bir;

    private String mem_sex;

    // DB 직접저장
    @Lob
    private byte[] mem_img;

    // 가입 경로 : "GOOGLE" | "KAKAO" | "LOCAL" 등 (ERD 컬럼명 그대로, mem_ 접두사 없음)
    private String provider;

}
