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

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RoomSceneResponse {
        private String roomId;

        private String roomName;

        private Object metadata;

        private RoomSceneModelResponse model;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RoomSceneModelResponse {
        private String fileName;

        private String contentType;

        private String dataBase64;
    }
}
