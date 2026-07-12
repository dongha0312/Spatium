import axios from "axios";

const API_BASE_PATH = "/img3d-api";

const imageTo3dApi = axios.create({
  baseURL: API_BASE_PATH,
  timeout: 0,
});

function detailMessage(detail) {
  if (typeof detail === "string") return detail;
  if (detail?.message) return detail.message;
  if (detail?.provider) return `${detail.provider} 처리에 실패했습니다.`;
  return null;
}

export function resolvePythonAssetUrl(path) {
  if (!path) return "";
  if (/^https?:\/\//i.test(path) || path.startsWith(API_BASE_PATH)) return path;
  return `${API_BASE_PATH}${path.startsWith("/") ? path : `/${path}`}`;
}

export function isCanceledImgTo3dRequest(error) {
  return axios.isCancel(error) || error?.code === "ERR_CANCELED";
}

export function getImgTo3dErrorMessage(error) {
  if (isCanceledImgTo3dRequest(error)) return "요청이 취소되었습니다.";

  const status = error?.response?.status;
  const detail = detailMessage(error?.response?.data?.detail);
  if (detail) return detail;

  const fallbackByStatus = {
    404: "FastAPI 요청 경로를 찾지 못했습니다. React 개발 서버를 재시작한 뒤 다시 시도해주세요.",
    413: "이미지 크기는 10MB 이하여야 합니다.",
    415: "PNG, JPG, WEBP 이미지만 사용할 수 있습니다.",
    422: "사진에서 요청한 가구를 찾지 못했거나 요청 값이 올바르지 않습니다.",
    500: "이미지 처리 중 오류가 발생했습니다.",
    502: "로컬 모델 실행에 실패했습니다.",
    503: "필요한 로컬 모델이나 실행 환경이 준비되지 않았습니다.",
    504: "모델 처리 시간이 초과되었습니다.",
  };
  return fallbackByStatus[status] || error?.message || "이미지→3D 서버에 연결하지 못했습니다.";
}

export async function removeBackground({ image, objectQuery, segmentationProvider, signal }) {
  const formData = new FormData();
  formData.append("image", image);
  formData.append("segmentation_provider", segmentationProvider);
  if (segmentationProvider === "grounded_sam2") {
    formData.append("object_query", objectQuery);
  } else if (/^[a-z][a-z\s-]*$/i.test(objectQuery)) {
    formData.append("target_class", objectQuery.toLowerCase());
  }

  const response = await imageTo3dApi.post("/v1/remove-background", formData, { signal });
  const data = response.data;
  const imageUrl = resolvePythonAssetUrl(data.download_url);
  const imageResponse = await imageTo3dApi.get(data.download_url, {
    responseType: "blob",
    signal,
  });
  const blob = imageResponse.data;
  const file = new File([blob], "segmented.png", { type: "image/png" });

  return {
    id: data.id,
    imageUrl,
    blob,
    file,
    segmentedObject: data.segmented_object,
    segmentationProvider: data.segmentation_provider,
    translatedQuery: data.translated_query,
    confidence: data.confidence,
  };
}

export async function generateModel({ image, provider, signal }) {
  const formData = new FormData();
  formData.append("image", image);
  formData.append("provider", provider);
  formData.append("remove_background", "false");
  formData.append("foreground_ratio", "0.85");
  if (provider === "local_stable_fast_3d") {
    formData.append("texture_resolution", "1024");
    formData.append("remesh", "none");
  } else {
    formData.append("mc_resolution", "256");
  }

  const response = await imageTo3dApi.post("/v1/image-to-3d", formData, { signal });
  const data = response.data;
  return {
    id: data.id,
    provider: data.provider,
    modelUrl: resolvePythonAssetUrl(data.download_url),
  };
}
