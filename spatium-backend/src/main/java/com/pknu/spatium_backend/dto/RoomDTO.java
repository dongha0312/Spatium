package com.pknu.spatium_backend.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

public class RoomDTO {

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RequestRoomCreateDTO {
        private String roomName;

        private String metadata;

        private String file;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ResponseRoomCreateDTO {
        private String roomId;

        private String roomName;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ResponseRoomSummaryDTO {
        private String roomId;

        private String roomName;

        private String area;

        private String thumbnailUrl;

        private String updatedAt;
    }
}
