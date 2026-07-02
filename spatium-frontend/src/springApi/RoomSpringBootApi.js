//  - springApi 변수 사용
import { springApi } from "../config/axiosInstance";

// 변경된 Room Json 데이터 백엔드 단에 저장시키기.
export const saveRoomMetadataJson = ({ apiUrl, metadataUrl, metadata }) =>
  springApi
    .put(apiUrl, metadata, {
      params: {
        metadataUrl,
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

// 룸 상세 조회
export const getRoomJsonData = (roomId) => {
  return springApi.get(`/api/rooms/${roomId}`);
}

// 새 룸 만들기 -> 필요한건가? DB 에 경로 저장하는 느낌 아닌가
export const postRoom = (projectId) => {
  return springApi.post(`/api/projects/${projectId}/rooms`)
}

// 룸 목록 조회
export const getRoomList = (projectId) => {
  return springApi.get(`/api/projects/${projectId}/rooms`)
}