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
@Table(name="Project")
@Getter
@Setter

@NoArgsConstructor
@AllArgsConstructor

@Builder

@ToString
public class Project {

    @Id
    private String proj_code;

    private String proj_mem;

    private String proj_name;

}
