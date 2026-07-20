import * as THREE from "three";
import { isUsdFloorMesh } from "./wallColliders";

// UI(3dEditor.js) 바닥 색상 팝오버에서 고를 수 있는 색상 프리셋.
export const FLOOR_COLORS = ["#D8C4A0", "#B08968", "#6B4A34", "#C9C9C9"];

// 방 모델의 바닥 mesh(isUsdFloorMesh) 색상을 지정한 색으로 바꾼다. color가 없으면(null)
// 처음 기록해둔 스캔/저장 당시의 기본 색으로 되돌린다.
export function applyRoomFloorColor(roomModel, color) {
  if (!roomModel) return;

  const nextColor = color ? new THREE.Color(color) : null;

  roomModel.traverse((child) => {
    if (!isUsdFloorMesh(child) || !child.material) return;

    const materials = Array.isArray(child.material)
      ? child.material
      : [child.material];

    materials.forEach((material) => {
      if (!material?.color) return;
      material.userData.spatiumDefaultFloorColor ||= material.color.clone();
      material.color.copy(
        nextColor || material.userData.spatiumDefaultFloorColor,
      );
      material.needsUpdate = true;
    });
  });
}
