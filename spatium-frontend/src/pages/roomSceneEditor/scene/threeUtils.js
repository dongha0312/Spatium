import * as THREE from "three";
import { CSS2DObject } from "three/examples/jsm/renderers/CSS2DRenderer.js";

// JSON으로 안전하게 깊은 복사한다 (metadata 원본을 수정하지 않고 편집본을 만들 때 사용).
export function cloneJsonValue(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

// 저장된 4x4 행렬(컬럼 4개 배열)을 THREE.Matrix4로 복원한다.
export function matrixFromColumns(columns) {
  const matrix = new THREE.Matrix4();
  matrix.fromArray(columns.flat());
  return matrix;
}

// THREE.Matrix4를 저장용 컬럼 4개 배열로 변환한다 (matrixFromColumns의 역변환).
export function columnsFromMatrix(matrix) {
  const values = matrix.toArray();
  return [
    values.slice(0, 4),
    values.slice(4, 8),
    values.slice(8, 12),
    values.slice(12, 16),
  ];
}

// 치수/디버그 라벨용 CSS2DObject(HTML div를 3D 씬 좌표에 붙이는 라벨)를 만든다.
export function createLabel(text, className = "furniture-label") {
  const div = document.createElement("div");
  div.className = className;
  div.textContent = text;
  return new CSS2DObject(div);
}

// material에 딸린 텍스처 등 하위 리소스까지 전부 dispose한다.
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

// object3D 트리를 순회하며 geometry/material(및 CSS2D label element)을 전부 정리한다.
// 오브젝트 교체/삭제 시 GPU 메모리 누수를 막기 위해 반드시 호출해야 한다.
export function disposeScene(scene) {
  scene.traverse((object) => {
    object.element?.remove?.();
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

// 카메라를 대상 오브젝트 전체가 한눈에 보이는 위치로 이동시킨다 (초기 로딩 후 방 전체를
// 보여줄 때 사용). 반환값(초기 프레이밍 거리)은 휠 줌아웃 최대 거리 제한(maxDistance)을
// 정하는 데 쓰인다.
export function frameObject(camera, controls, object) {
  const bounds = new THREE.Box3().setFromObject(object);
  if (bounds.isEmpty()) return null;

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
  return distance;
}

// metadata의 item(가구/문/창문)에 저장된 transform 행렬을 position/quaternion/scale로 분해한다.
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
