import { CSS2DObject } from "three/examples/jsm/renderers/CSS2DRenderer.js";

// 선택한 가구의 가로/세로/높이 치수를 보여주는 라벨(기본은 숨김, showMeasurements일 때만 표시).
export function createDimensionLabel() {
  const element = document.createElement("div");
  element.className = "dimension-label";
  const label = new CSS2DObject(element);
  label.visible = false;
  return label;
}

// 방 전체의 면적/치수 등을 보여주는 라벨.
export function createRoomDimensionLabel(text) {
  const element = document.createElement("div");
  element.className = "room-dimension-label";
  element.textContent = text;
  return new CSS2DObject(element);
}

// 미터 단위 값을 cm 문자열로 포맷한다 (최소 1cm로 표시).
export function formatCentimeters(value) {
  return `${Math.max(Math.round(value * 100), 1)} cm`;
}

export function formatSquareMeters(value) {
  return Number.isFinite(value) ? `${value.toFixed(2)} m2` : "-";
}

export function formatPyung(value) {
  return Number.isFinite(value) ? `${value.toFixed(1)} 평` : "-";
}

// 드래그/회전 중에도 치수 라벨 값이 흔들리지 않도록, metadata에 저장된 원래 dimensions를
// 우선 쓰고 없으면 localObb 크기, 그것도 없으면 fallback을 쓴다.
export function stableDimensionsForObject(object, fallbackSize) {
  const dimensions = object?.userData.roomItem?.dimensions || {};
  const localObbSize = object?.userData.localObb?.halfSize
    ?.clone()
    .multiplyScalar(2);

  return {
    width: Number(dimensions.x) || localObbSize?.x || fallbackSize.x,
    height: Number(dimensions.y) || localObbSize?.y || fallbackSize.y,
    depth: Number(dimensions.z) || localObbSize?.z || fallbackSize.z,
  };
}
