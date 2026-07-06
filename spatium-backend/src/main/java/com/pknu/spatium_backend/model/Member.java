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
    //  - 비밀번호 해시가 로그에 남지 않도록 toString에서 제외
    @ToString.Exclude
    private String mem_pass;

    // 생년월일(개인정보) : 로그 노출 방지
    @ToString.Exclude
    private String mem_bir;

    private String mem_sex;

    // DB 직접저장
    //  - 대용량 바이너리가 로그를 오염시키지 않도록 toString에서 제외
    @Lob
    @ToString.Exclude
    private byte[] mem_img;

    // 가입 경로 : "GOOGLE" | "KAKAO" | "LOCAL" 등 (ERD 컬럼명 그대로, mem_ 접두사 없음)
    private String provider;

}
