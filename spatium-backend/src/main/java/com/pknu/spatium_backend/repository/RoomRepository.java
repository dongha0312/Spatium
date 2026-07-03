package com.pknu.spatium_backend.repository;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import com.pknu.spatium_backend.model.Room;


@Repository
public interface RoomRepository extends JpaRepository<Room, String>{

    @Modifying
    @Query("DELETE FROM Room r WHERE r.room_proj = :projectId")
    void deleteByRoomProj(@Param("projectId") String projectId);

    @Query("SELECT r FROM Room r WHERE r.room_id = :roomId AND r.room_proj = :projectId")
    Optional<Room> findByRoomIdAndProjectId(
            @Param("roomId") String roomId,
            @Param("projectId") String projectId);

}
