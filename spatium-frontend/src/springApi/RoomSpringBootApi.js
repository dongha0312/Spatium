import { springApi } from "../config/axiosInstance";
import { throwApiError, unwrapApiData } from "../utils/apiResponse";

export const saveRoomMetadataJson = ({ projectId, roomId, metadata, area }) => {
  const formData = new FormData();
  const metadataFile = new Blob([JSON.stringify(metadata)], {
    type: "application/json",
  });

  formData.append("projectId", projectId);
  formData.append("roomId", roomId);
  if (Number.isFinite(area)) {
    formData.append("area", String(area));
  }
  formData.append("metadata", metadataFile, "metadata.json");

  return springApi
    .post("/api/rooms/save", formData)
    .then(unwrapApiData)
    .catch(throwApiError);
};

export const getRoomJsonData = (roomId) =>
  springApi.get(`/api/rooms/${roomId}`).then(unwrapApiData).catch(throwApiError);

export const postRoom = ({ projectId, roomName, metadata, file }) => {
  const formData = new FormData();
  formData.append("metadata", metadata);
  formData.append("file", file);

  return springApi
    .post(`/api/projects/${projectId}/rooms`, formData, {
      params: { roomName },
    })
    .then(unwrapApiData)
    .catch(throwApiError);
};

export const getRoomList = (projectId, params = {}) =>
  springApi
    .get(`/api/projects/${projectId}/rooms`, { params })
    .then(unwrapApiData)
    .catch(throwApiError);

// 내 방 삭제
export const deleteRoom = ({ projectId, roomId, accessToken }) => {
  return springApi
    .delete("/api/rooms", {
      data: {
        projectId,
        roomId,
      },
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    })
    .then((response) => response.data)
    .catch((error) => {
      const responseData = error.response?.data;
      const message =
        typeof responseData === "string"
          ? responseData
          : responseData?.message || error.message;

      throw new Error(message);
    });
};
