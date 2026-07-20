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
export function disposeMaterial(material, disposedTextures = null) {
  const ownsTextures = !material.userData?.spatiumSharedTextures;
  Object.values(material).forEach((value) => {
    if (
      ownsTextures &&
      value &&
      typeof value === "object" &&
      typeof value.dispose === "function"
    ) {
      if (disposedTextures?.has(value)) return;
      disposedTextures?.add(value);
      value.dispose();
    }
  });
  material.dispose();
}

// object3D 트리를 순회하며 geometry/material(및 CSS2D label element)을 전부 정리한다.
// 오브젝트 교체/삭제 시 GPU 메모리 누수를 막기 위해 반드시 호출해야 한다.
export function disposeScene(scene) {
  const disposedGeometries = new Set();
  const disposedMaterials = new Set();
  const disposedTextures = new Set();
  scene.traverse((object) => {
    object.element?.remove?.();
    if (object.geometry && !disposedGeometries.has(object.geometry)) {
      disposedGeometries.add(object.geometry);
      object.geometry.dispose();
    }
    if (object.material) {
      if (Array.isArray(object.material)) {
        object.material.forEach((material) => {
          if (disposedMaterials.has(material)) return;
          disposedMaterials.add(material);
          disposeMaterial(material, disposedTextures);
        });
      } else if (!disposedMaterials.has(object.material)) {
        disposedMaterials.add(object.material);
        disposeMaterial(object.material, disposedTextures);
      }
    }
  });
}

// 카메라를 대상 오브젝트 전체가 한눈에 보이는 위치로 이동시킨다 (초기 로딩 후 방 전체를
// 보여줄 때 사용). 반환값(초기 프레이밍 거리)은 휠 줌아웃 최대 거리 제한(maxDistance)을
// 정하는 데 쓰인다. boundsOverride를 주면 raw bounding box 대신 그 박스로 프레이밍한다
// — 스캔 모델에 섞인 outlier mesh가 raw 박스를 부풀려 카메라가 수백 km 밖에 놓이는
// 것을 막기 위함(framingBoundsFromMeasurements 참고).
export function frameObject(camera, controls, object, boundsOverride = null) {
  const bounds =
    boundsOverride && !boundsOverride.isEmpty()
      ? boundsOverride
      : new THREE.Box3().setFromObject(object);
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

// 저장된 transform에서 나올 수 있는 정상적인 scale 범위. 크기 슬라이더는 10~500cm
// 범위라 정상 scale은 이 안에 들어온다. 이걸 벗어나면(과거 버그로 오염된 저장 데이터)
// scale을 신뢰하지 않고 1로 리셋한다 — 의도된 크기는 dimensions에 따로 저장돼 있어서
// scale 1이 곧 "원래 치수 그대로"다. 실제로 scale이 10^5까지 오염된 가구가 씬 bounding
// box를 수백 km로 부풀리는 사례가 있었다.
const SANE_SCALE_MIN = 0.01;
const SANE_SCALE_MAX = 25;

function isSaneScaleComponent(value) {
  return (
    Number.isFinite(value) &&
    Math.abs(value) >= SANE_SCALE_MIN &&
    Math.abs(value) <= SANE_SCALE_MAX
  );
}

// metadata의 item(가구/문/창문)에 저장된 transform 행렬을 position/quaternion/scale로 분해한다.
// 오염된 scale(비정상적으로 크거나 작거나 NaN)은 1로 리셋한다.
export function decomposeRoomTransform(item) {
  const position = new THREE.Vector3();
  const quaternion = new THREE.Quaternion();
  const scale = new THREE.Vector3();
  matrixFromColumns(item.transform.columns).decompose(
    position,
    quaternion,
    scale,
  );

  if (
    !isSaneScaleComponent(scale.x) ||
    !isSaneScaleComponent(scale.y) ||
    !isSaneScaleComponent(scale.z)
  ) {
    console.warn(
      "[roomSceneEditor] Reset corrupted saved scale to 1:",
      item.name || item.category || "item",
      scale.toArray(),
    );
    scale.set(1, 1, 1);
  }

  return { position, quaternion, scale };
}
