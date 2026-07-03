package com.pknu.spatium_backend.repository;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import com.pknu.spatium_backend.model.Room;


@Repository
public interface RoomRepository extends JpaRepository<Room, String>{

    @Modifying
    @Query("DELETE FROM Room r WHERE r.room_proj = :projectId")
    void deleteByRoomProj(String projectId);

}
