import * as THREE from "three";
import { isUsdFloorMesh } from "./wallColliders";

// UI(3dEditor.js) 바닥 색상 팝오버에서 고를 수 있는 색상 프리셋.
export const FLOOR_COLORS = ["#D8C4A0", "#B08968", "#6B4A34", "#C9C9C9"];

// 방 모델의 바닥 mesh(isUsdFloorMesh) 색상을 지정한 색으로 바꾼다. color가 없으면(null)
// 아무것도 하지 않는다 — 즉 사용자가 바닥 색을 따로 지정하지 않으면 스캔 당시의 원래
// 색이 유지된다(applyRoomWallColor와 동일한 패턴).
export function applyRoomFloorColor(roomModel, color) {
  if (!roomModel || !color) return;

  const nextColor = new THREE.Color(color);

  roomModel.traverse((child) => {
    if (!isUsdFloorMesh(child) || !child.material) return;

    const materials = Array.isArray(child.material)
      ? child.material
      : [child.material];

    materials.forEach((material) => {
      if (!material?.color) return;
      material.color.copy(nextColor);
      material.needsUpdate = true;
    });
  });
}
