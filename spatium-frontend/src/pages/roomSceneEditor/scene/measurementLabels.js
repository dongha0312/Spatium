import { CSS2DObject } from "three/examples/jsm/renderers/CSS2DRenderer.js";

export function createDimensionLabel() {
  const element = document.createElement("div");
  element.className = "dimension-label";
  const label = new CSS2DObject(element);
  label.visible = false;
  return label;
}

export function createRoomDimensionLabel(text) {
  const element = document.createElement("div");
  element.className = "room-dimension-label";
  element.textContent = text;
  return new CSS2DObject(element);
}

export function formatCentimeters(value) {
  return `${Math.max(Math.round(value * 100), 1)} cm`;
}

export function formatSquareMeters(value) {
  return Number.isFinite(value) ? `${value.toFixed(2)} m2` : "-";
}

export function formatPyung(value) {
  return Number.isFinite(value) ? `${value.toFixed(1)} 평` : "-";
}

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
