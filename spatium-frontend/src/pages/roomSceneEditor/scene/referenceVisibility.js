import * as THREE from "three";
import { CSS2DObject } from "three/examples/jsm/renderers/CSS2DRenderer.js";
import { yawDegreesFromDirection } from "./editorTransforms";

// 문/창문 옆에 방향 정보(법선/카메라 각도)를 보여주는 디버그 라벨 (showReferenceLabels일 때만 사용).
export function createReferenceDebugLabel() {
  const element = document.createElement("div");
  element.className = "reference-debug-label";
  const label = new CSS2DObject(element);
  label.visible = true;
  return label;
}

// 카메라 시야를 가리는 문/창문을 반투명하게 만든다(hidden=true). 원래 상태(opacity 등)는
// 처음 호출될 때 material.userData에 저장해두고, hidden=false가 되면 그 값으로 복원한다.
export function applyReferencePreviewVisibility(reference, hidden) {
  // 매 프레임 호출되므로, hidden 상태가 지난번과 같으면 traverse/material 갱신을
  // 통째로 건너뛴다. 교체로 새로 만들어진 오브젝트는 이 값이 없어 항상 첫 적용을 탄다.
  if (reference.userData.spatiumPreviewHidden === hidden) return;
  reference.userData.spatiumPreviewHidden = hidden;

  const debugLabel = reference.userData.debugLabel;

  reference.traverse?.((child) => {
    if (child === reference || child === debugLabel) return;
    if (child.element?.classList?.contains("reference-debug-label")) return;
    if (
      child.isMesh ||
      child.isLine ||
      child.isLineSegments ||
      child.isSprite
    ) {
      if (child.userData.spatiumOriginalVisible == null) {
        child.userData.spatiumOriginalVisible = child.visible;
      }

      child.visible = hidden ? true : child.userData.spatiumOriginalVisible;

      const materials = Array.isArray(child.material)
        ? child.material
        : [child.material];

      materials.forEach((material) => {
        if (!material) return;
        if (!material.userData.spatiumOriginalReferenceState) {
          material.userData.spatiumOriginalReferenceState = {
            opacity: material.opacity,
            transparent: material.transparent,
            depthWrite: material.depthWrite,
            alphaTest: material.alphaTest,
            visible: material.visible,
          };
        }

        const original = material.userData.spatiumOriginalReferenceState;
        material.visible = hidden ? true : original.visible;
        material.transparent = hidden || original.transparent;
        material.opacity = hidden ? 0.08 : original.opacity;
        material.depthWrite = hidden ? false : original.depthWrite;
        material.alphaTest = hidden ? 0 : original.alphaTest;
        material.needsUpdate = true;
      });
    }
  });
}

// 카메라가 문/창문의 roomFacingNormal 반대편(바깥쪽)에 있으면 hidden:true를 반환한다.
// roomFacingNormal이 없으면(초기화 안 됐으면) 항상 hidden:false — 즉 절대 흐려지지 않는다.
export function referenceVisibilityState(reference, camera) {
  const normal = reference.userData.roomFacingNormal?.clone().setY(0);
  if (!normal || normal.lengthSq() < 1e-8) {
    return {
      hidden: false,
      dot: null,
      normalYaw: null,
      toCameraYaw: null,
    };
  }

  const toCamera = camera.position.clone().sub(reference.position).setY(0);
  if (toCamera.lengthSq() < 1e-8) {
    return {
      hidden: false,
      dot: null,
      normalYaw: yawDegreesFromDirection(normal),
      toCameraYaw: null,
    };
  }

  const normalizedNormal = normal.normalize();
  const normalizedToCamera = toCamera.normalize();
  const dot = normalizedToCamera.dot(normalizedNormal);

  return {
    hidden: dot < 0,
    dot,
    normalYaw: yawDegreesFromDirection(normalizedNormal),
    toCameraYaw: yawDegreesFromDirection(normalizedToCamera),
  };
}

function formatDebugValue(value, suffix = "") {
  return value == null ? "--" : `${value}${suffix}`;
}

// 디버그 라벨 텍스트를 현재 상태(법선/카메라 각도/숨김 여부)로 갱신한다.
export function updateReferenceDebugLabel(reference, state) {
  const element = reference.userData.debugLabel?.element;
  if (!element) return;

  const type = reference.userData.sourceType || "ref";
  const index = Number(reference.userData.sourceIndex) + 1;
  const labelIndex = Number.isFinite(index) ? index : "";
  const normalYaw =
    state.normalYaw == null ? null : Math.round(state.normalYaw);
  const toCameraYaw =
    state.toCameraYaw == null ? null : Math.round(state.toCameraYaw);
  const dot = state.dot == null ? null : state.dot.toFixed(2);

  element.textContent = `${type}${labelIndex} n:${formatDebugValue(
    normalYaw,
    "째",
  )} cam:${formatDebugValue(toCameraYaw, "째")} dot:${formatDebugValue(
    dot,
  )} ${state.hidden ? "hide" : "show"}`;
}

// 문/창문 localObb에서 가장 얇은 수평 축(=두께 방향)을 찾아 월드 좌표계의 법선 벡터로 변환한다.
// 이 축이 곧 "문/창문 패널이 바라보는 방향"이 된다.
export function referencePlaneNormal(reference) {
  const localObb = reference.userData.localObb;
  if (!localObb) return null;

  const axes = [
    { name: "x", axis: new THREE.Vector3() },
    { name: "y", axis: new THREE.Vector3() },
    { name: "z", axis: new THREE.Vector3() },
  ];
  localObb.rotation.extractBasis(axes[0].axis, axes[1].axis, axes[2].axis);

  const horizontalAxes = axes
    .map((entry) => ({
      ...entry,
      halfSize: localObb.halfSize[entry.name],
      horizontal: entry.axis.clone().setY(0),
    }))
    .filter((entry) => entry.horizontal.lengthSq() > 1e-8)
    .sort((a, b) => a.halfSize - b.halfSize);

  const thinnestHorizontalAxis = horizontalAxes[0];
  if (!thinnestHorizontalAxis) return null;

  return thinnestHorizontalAxis.horizontal
    .normalize()
    .applyQuaternion(reference.quaternion)
    .setY(0)
    .normalize();
}

// 문/창문의 roomFacingNormal(방 안쪽을 향하는 법선)을 계산해서 userData에 저장한다.
// referencePlaneNormal()로 얇은 축을 구한 뒤, 방 중심을 향하는 쪽으로 부호를 맞춘다.
// 초기 로딩과 교체(replace) 양쪽에서 반드시 호출해야 카메라 각도에 따른 흐려짐이 동작한다.
export function initializeReferenceFacingNormal(reference, roomCenter) {
  const localNormal = referencePlaneNormal(reference);

  if (!localNormal || localNormal.lengthSq() < 1e-8) {
    reference.userData.roomFacingNormal = null;
    return;
  }

  const normal = localNormal.normalize();
  const toRoomCenter = roomCenter.clone().sub(reference.position).setY(0);

  if (toRoomCenter.lengthSq() > 1e-8 && normal.dot(toRoomCenter) < 0) {
    normal.multiplyScalar(-1);
  }

  reference.userData.roomFacingNormal = normal;
}
