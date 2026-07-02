package com.pknu.spatium_backend.model;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.ToString;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;

@Entity
@Table(name="Room")
@Getter
@Setter

@NoArgsConstructor
@AllArgsConstructor

@Builder

@ToString
public class Room {
    
    @Id
    private String room_id;

    private String proj_code;

    // BLOB 데이터 타입으로 매핑 -> room json 파일 위치 URL
    @Lob
    private byte[] room_path;

    private String room_name;

}
