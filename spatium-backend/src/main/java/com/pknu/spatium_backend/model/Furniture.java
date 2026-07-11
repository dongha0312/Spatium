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
@Table(name="Furniture")
@Getter
@Setter

@NoArgsConstructor
@AllArgsConstructor

@Builder

@ToString
public class Furniture {

    @Id
    private String fur_code;

    private String fur_name;

    private String fur_color;

    @Lob
    private byte[] fur_path;

    @Lob
    private byte[] fur_img;


}
