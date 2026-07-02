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

    private String mem_pass;
    
    private String mem_bir;

    private String mem_sex;

    @Lob
    private byte[] mem_img;

    private String provider;

}
