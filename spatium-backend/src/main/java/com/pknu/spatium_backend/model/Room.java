package com.pknu.spatium_backend.model;

import java.time.LocalDateTime;

import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.ToString;
import jakarta.persistence.Id;

@Entity
@Table(name = "Room")
@Getter
@Setter

@NoArgsConstructor
@AllArgsConstructor

@Builder

@ToString
public class Room {

    @Id
    private String room_id;

    private String room_proj;

    // room json/usdz 파일 저장 위치
    private String room_path;

    private String room_name;

    private String room_area;

    @CreationTimestamp
    @Column(name = "room_created", updatable = false)
    private LocalDateTime room_created;

    @UpdateTimestamp
    private LocalDateTime room_modified;

}
