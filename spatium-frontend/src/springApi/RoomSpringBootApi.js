//  - springApi 변수 사용
import { springApi } from "../config/axiosInstance";

// 저장 테스트용 삭제 할 예정
// // 변경된 Room Json 데이터 백엔드 단에 저장시키기.
// export const saveRoomMetadataJson = ({ apiUrl, metadataUrl, metadata }) =>
//   springApi
//     .put(apiUrl, metadata, {
//       params: {
//         metadataUrl,
//       },
//     })
//     .then((response) => response.data)
//     .catch((error) => {
//       const responseData = error.response?.data;
//       const message =
//         typeof responseData === "string"
//           ? responseData
//           : responseData?.message || error.message;

//       throw new Error(message);
//     });

export const saveRoomMetadataJson = ({
  projectId,
  roomId,
  metadata,
  accessToken,
}) => {
  const formData = new FormData();
  const metadataFile = new Blob([JSON.stringify(metadata)], {
    type: "application/json",
  });

  formData.append("projectId", projectId);
  formData.append("roomId", roomId);
  formData.append("metadata", metadataFile, "metadata.json");

  return springApi
    .post("/api/rooms/save", formData, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "multipart/form-data",
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

// 룸 상세 조회
export const getRoomJsonData = (roomId) => {
  return springApi.get(`/api/rooms/${roomId}`);
};

// 새 룸 만들기 -> 필요한건가? DB 에 경로 저장하는 느낌 아닌가
export const postRoom = (projectId) => {
  return springApi.post(`/api/projects/${projectId}/rooms`);
};

// 룸 목록 조회
export const getRoomList = (projectId) => {
  return springApi.get(`/api/projects/${projectId}/rooms`);
};
