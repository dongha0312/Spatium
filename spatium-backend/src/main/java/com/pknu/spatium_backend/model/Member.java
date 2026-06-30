package com.pknu.spatium_backend.model;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.ToString;

@Entity
@ToString
public class Member {

    @Id
    private String mem_id;

    private String mem_email;

    private String mem_nick;

    private String mem_path;

    private String mem_bir;

    private String mem_sex;

}
