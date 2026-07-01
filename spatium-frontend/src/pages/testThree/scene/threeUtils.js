import * as THREE from "three";
import { CSS2DObject } from "three/examples/jsm/renderers/CSS2DRenderer.js";

export function cloneJsonValue(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

export function matrixFromColumns(columns) {
  const matrix = new THREE.Matrix4();
  matrix.fromArray(columns.flat());
  return matrix;
}

export function columnsFromMatrix(matrix) {
  const values = matrix.toArray();
  return [
    values.slice(0, 4),
    values.slice(4, 8),
    values.slice(8, 12),
    values.slice(12, 16),
  ];
}

export function createLabel(text, className = "furniture-label") {
  const div = document.createElement("div");
  div.className = className;
  div.textContent = text;
  return new CSS2DObject(div);
}

export function disposeMaterial(material) {
  Object.values(material).forEach((value) => {
    if (
      value &&
      typeof value === "object" &&
      typeof value.dispose === "function"
    ) {
      value.dispose();
    }
  });
  material.dispose();
}

export function disposeScene(scene) {
  scene.traverse((object) => {
    if (object.geometry) object.geometry.dispose();
    if (object.material) {
      if (Array.isArray(object.material)) {
        object.material.forEach(disposeMaterial);
      } else {
        disposeMaterial(object.material);
      }
    }
  });
}

export function frameObject(camera, controls, object) {
  const bounds = new THREE.Box3().setFromObject(object);
  if (bounds.isEmpty()) return;

  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const maxDimension = Math.max(size.x, size.y, size.z, 1);
  const distance =
    (maxDimension / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2))) *
    1.35;

  camera.position
    .copy(center)
    .add(new THREE.Vector3(0.7, 0.45, 1).normalize().multiplyScalar(distance));
  camera.near = Math.max(distance / 1000, 0.01);
  camera.far = distance * 100;
  camera.updateProjectionMatrix();
  controls.target.copy(center);
  controls.update();
}

export function decomposeRoomTransform(item) {
  const position = new THREE.Vector3();
  const quaternion = new THREE.Quaternion();
  const scale = new THREE.Vector3();
  matrixFromColumns(item.transform.columns).decompose(
    position,
    quaternion,
    scale,
  );
  return { position, quaternion, scale };
}
