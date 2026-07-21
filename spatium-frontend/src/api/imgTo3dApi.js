import axios from "axios";
import { springApi } from "../config/axiosInstance";

const AI_METADATA_HEADER = "x-spatium-ai-metadata";

function detailMessage(detail) {
  if (typeof detail === "string") return detail;
  if (detail?.message) return detail.message;
  if (detail?.provider) return `${detail.provider} 처리에 실패했습니다.`;
  return null;
}

function decodeAiMetadata(encoded) {
  if (!encoded) return {};
  try {
    const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    const bytes = Uint8Array.from(atob(padded), (character) =>
      character.charCodeAt(0),
    );
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch (error) {
    console.warn("AI metadata 헤더를 해석하지 못했습니다.", error);
    return {};
  }
}

function responseMetadata(response) {
  return decodeAiMetadata(response.headers?.[AI_METADATA_HEADER]);
}

function requestId() {
  return window.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`;
}

export function isCanceledImgTo3dRequest(error) {
  return axios.isCancel(error) || error?.code === "ERR_CANCELED";
}

export function getImgTo3dErrorMessage(error) {
  if (isCanceledImgTo3dRequest(error)) return "요청이 취소되었습니다.";

  const status = error?.response?.status;
  const responseData = error?.response?.data;
  const detail =
    detailMessage(responseData?.detail) ||
    (typeof responseData?.message === "string" ? responseData.message : null);
  if (detail) return detail;

  const fallbackByStatus = {
    400: "이미지 또는 요청 값을 확인해주세요.",
    401: "로그인이 만료되었습니다. 다시 로그인해주세요.",
    404: "AI 요청 경로를 찾지 못했습니다.",
    413: "이미지 크기는 10MB 이하여야 합니다.",
    415: "PNG, JPG, WEBP 이미지만 사용할 수 있습니다.",
    422: "사진에서 요청한 가구를 찾지 못했거나 요청 값이 올바르지 않습니다.",
    // 같은 IP에서 이미 GPU 작업이 진행 중인 경우 (백엔드 GpuAccessLimiter)
    //  - 같은 공유기/학내망을 쓰는 다른 사용자의 작업일 수도 있어 문구를 단정하지 않는다.
    429: "현재 다른 생성 작업이 진행 중입니다. 완료된 후 다시 시도해주세요.",
    500: "이미지 처리 중 오류가 발생했습니다.",
    502: "AI 모델 실행에 실패했습니다.",
    503: "필요한 AI 모델이나 실행 환경이 준비되지 않았습니다.",
    504: "모델 처리 시간이 초과되었습니다.",
  };
  return fallbackByStatus[status] || error?.message || "AI 서버에 연결하지 못했습니다.";
}

export async function removeBackground({
  image,
  objectQuery,
  segmentationProvider,
  signal,
}) {
  const formData = new FormData();
  formData.append("image", image);
  formData.append("segmentation_provider", segmentationProvider);
  if (segmentationProvider === "grounded_sam2") {
    formData.append("object_query", objectQuery);
  } else {
    formData.append("target_class", "auto");
  }

  const response = await springApi.post("/api/ai/remove-background", formData, {
    responseType: "blob",
    signal,
    timeout: 0,
  });
  const blob = response.data;
  const metadata = responseMetadata(response);
  const imageUrl = URL.createObjectURL(blob);
  const file = new File([blob], "segmented.png", { type: "image/png" });

  return {
    id: requestId(),
    imageUrl,
    blob,
    file,
    segmentedObject: metadata.segmented_object,
    segmentationProvider: metadata.segmentation_provider,
    translatedQuery: metadata.translated_query,
    confidence: metadata.confidence,
  };
}

export async function generateModel({
  image,
  provider,
  mcResolution = "256",
  textureResolution = "1024",
  remesh = "none",
  signal,
}) {
  const formData = new FormData();
  formData.append("image", image);
  formData.append("provider", provider);
  formData.append("remove_background", "false");
  formData.append("foreground_ratio", "0.85");
  if (provider === "local_stable_fast_3d") {
    formData.append("texture_resolution", String(textureResolution));
    formData.append("remesh", remesh);
  } else {
    formData.append("mc_resolution", String(mcResolution));
  }

  const response = await springApi.post("/api/ai/image-to-3d", formData, {
    responseType: "blob",
    signal,
    timeout: 0,
  });
  const blob = response.data;
  const metadata = responseMetadata(response);
  return {
    id: requestId(),
    provider: metadata.provider || provider,
    blob,
    modelUrl: URL.createObjectURL(blob),
  };
}
