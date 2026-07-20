import { springApi } from "../config/axiosInstance";
import { throwApiError, unwrapApiData } from "../utils/apiResponse";

// 기본 제공 가구 카탈로그 조회 (기존 /data/furniture_catalog.json 대체)
export const getFurnitureCatalog = () =>
  springApi.get("/api/furniture").then(unwrapApiData).catch(throwApiError);

// 로그인한 회원이 생성한 사용자 가구 목록 조회 (내 가구 조회)
export const getUserFurnitureCatalog = () =>
  springApi.get("/api/furniture/user").then(unwrapApiData).catch(throwApiError);

// 내 가구 생성
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

// 내 가구 삭제 (soft delete) — 성공 시 삭제된 furCode 문자열을 반환한다
export const deleteUserFurniture = (furCode) =>
  springApi
    .delete(`/api/furniture/${encodeURIComponent(furCode)}`)
    .then(unwrapApiData)
    .catch(throwApiError);
