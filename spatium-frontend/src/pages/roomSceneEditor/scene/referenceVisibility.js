import * as THREE from "three";
import { CSS2DObject } from "three/examples/jsm/renderers/CSS2DRenderer.js";
import { yawDegreesFromDirection } from "./editorTransforms";

export function createReferenceDebugLabel() {
  const element = document.createElement("div");
  element.className = "reference-debug-label";
  const label = new CSS2DObject(element);
  label.visible = true;
  return label;
}

export function applyReferencePreviewVisibility(reference, hidden) {
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
