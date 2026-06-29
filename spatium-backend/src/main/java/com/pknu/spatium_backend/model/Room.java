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

    private String room_mem;

    // BLOB 데이터 타입으로 매핑
    @Lob
    private byte[] room_3d;

}
