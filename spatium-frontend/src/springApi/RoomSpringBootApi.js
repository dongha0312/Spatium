//  - springApi 변수 사용
import { springApi } from "../config/axiosInstance";

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
