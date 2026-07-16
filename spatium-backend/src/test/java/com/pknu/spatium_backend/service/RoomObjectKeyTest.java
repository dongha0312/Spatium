package com.pknu.spatium_backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;

import org.junit.jupiter.api.Test;

class RoomObjectKeyTest {

    @Test
    void derivesTheTwoFixedRoomFilesFromTheStoredPrefix() {
        String prefix = "rooms/member-1/project-1/room-1";

        assertEquals(
                List.of(prefix + "/metadata.json", prefix + "/scene.usdz"),
                RoomService.roomObjectKeys(prefix));
    }
}
