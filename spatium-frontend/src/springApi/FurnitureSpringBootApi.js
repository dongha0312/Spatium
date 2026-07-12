import { springApi } from "../config/axiosInstance";
import { throwApiError, unwrapApiData } from "../utils/apiResponse";

// 기본 제공 가구 카탈로그 조회 (기존 /data/furniture_catalog.json 대체)
export const getFurnitureCatalog = () =>
  springApi
    .get("/api/furniture")
    .then(unwrapApiData)
    .catch(throwApiError);

export const createUserFurniture = ({ file, metadata }) => {
  const formData = new FormData();
  formData.append("file", file);
  formData.append(
    "metadata",
    new Blob([JSON.stringify(metadata)], { type: "application/json" }),
  );

  return springApi
    .post("/api/furniture", formData)
    .then(unwrapApiData)
    .catch(throwApiError);
};
