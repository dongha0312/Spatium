import * as THREE from "three";
import { canTransformObject } from "./collision";
import { referenceFallbackThickness, sceneColor } from "./sceneConfig";
import { columnsFromMatrix } from "./threeUtils";

export const DEFAULT_FURNITURE_DIMENSIONS = { x: 0.8, y: 0.8, z: 0.8 };
export const REFERENCE_CATEGORIES = new Set(["door", "window"]);

// API가 내려준 base64 모델 데이터를 blob URL로 바꿔서 로더에 넘길 수 있게 한다.
export function base64ToObjectUrl(
  base64,
  contentType = "application/octet-stream",
) {
  const binary = window.atob(base64);
  const bytes = [];

  for (let offset = 0; offset < binary.length; offset += 1024) {
    const slice = binary.slice(offset, offset + 1024);
    const chunk = new Uint8Array(slice.length);

    for (let index = 0; index < slice.length; index += 1) {
      chunk[index] = slice.charCodeAt(index);
    }

    bytes.push(chunk);
  }

  return URL.createObjectURL(new Blob(bytes, { type: contentType }));
}

// 가구 dimensions를 정규화한다 (없거나 0이면 기본값, 최소 4cm는 보장).
export function normalizedDimensions(dimensions = {}) {
  return {
    x: Math.max(Number(dimensions.x) || DEFAULT_FURNITURE_DIMENSIONS.x, 0.04),
    y: Math.max(Number(dimensions.y) || DEFAULT_FURNITURE_DIMENSIONS.y, 0.04),
    z: Math.max(Number(dimensions.z) || DEFAULT_FURNITURE_DIMENSIONS.z, 0.04),
  };
}

// 문/창문 dimensions를 정규화한다. 두께(z)는 스캔값이 fallback의 1.5배를 넘으면
// (비정상적으로 두꺼운 값으로 보고) fallback 두께를 대신 쓴다.
export function normalizedReferenceDimensions(category, dimensions = {}) {
  const fallbackThickness = referenceFallbackThickness(category);
  const thickness = Number(dimensions.z);

  return {
    x: Math.max(Number(dimensions.x) || DEFAULT_FURNITURE_DIMENSIONS.x, 0.04),
    y: Math.max(Number(dimensions.y) || DEFAULT_FURNITURE_DIMENSIONS.y, 0.04),
    z:
      Number.isFinite(thickness) &&
      thickness > 0 &&
      thickness <= fallbackThickness * 1.5
        ? thickness
        : fallbackThickness,
  };
}

// position/quaternion/scale을 합성해서 저장용 행렬(컬럼 배열, 소수점 6자리 반올림)로 만든다.
export function roundedTransform(
  position,
  quaternion = new THREE.Quaternion(),
  scale = new THREE.Vector3(1, 1, 1),
) {
  const matrix = new THREE.Matrix4().compose(position, quaternion, scale);

  return {
    columns: columnsFromMatrix(matrix).map((column) =>
      column.map((value) => Number(value.toFixed(6))),
    ),
  };
}

// 카탈로그 항목 + 배치 위치로부터 저장 가능한 room item(가구) 데이터를 만든다.
// 새 가구를 추가할 때 이 결과가 그대로 편집 대상 item이 된다.
export function createFurnitureItemFromCatalog(
  catalogItem,
  position,
  quaternion = new THREE.Quaternion(),
  scale = new THREE.Vector3(1, 1, 1),
) {
  const dimensions = normalizedDimensions(catalogItem.dimensions);

  return {
    catalogId: catalogItem.id,
    name: catalogItem.name,
    category: catalogItem.category,
    path: catalogItem.path || catalogItem.modelUrl,
    modelUrl: catalogItem.modelUrl,
    dimensions,
    transform: roundedTransform(position, quaternion, scale),
  };
}

// 방의 바닥 Y좌표를 추정한다. metadata에 저장된 가구들의 (위치 - 높이/2) 중 최솟값을
// 우선 쓰고, 가구가 하나도 없으면 방 모델의 bounding box 최저점을 쓴다.
export function estimateFloorY(metadataObjects, roomModel) {
  const objectFloorYs = (metadataObjects || [])
    .map((item) => {
      const y = Number(item.transform?.columns?.[3]?.[1]);
      const height = Number(item.dimensions?.y);
      return Number.isFinite(y) && Number.isFinite(height)
        ? y - height / 2
        : null;
    })
    .filter((value) => value != null);

  if (objectFloorYs.length) {
    return Math.min(...objectFloorYs);
  }

  const bounds = new THREE.Box3().setFromObject(roomModel);
  return bounds.isEmpty() ? 0 : bounds.min.y;
}

// 각도를 -180 ~ 180 범위로 정규화한다 (예: 190 -> -170).
export function normalizeRotationDegrees(degrees) {
  const normalized = THREE.MathUtils.euclideanModulo(degrees + 180, 360) - 180;
  return Math.round(normalized);
}

// 오브젝트의 현재 Y축 회전(quaternion)을 -180~180도 정수로 변환한다.
export function rotationDegreesFromObject(object) {
  if (!object) return 0;

  const euler = new THREE.Euler().setFromQuaternion(object.quaternion, "YXZ");
  return normalizeRotationDegrees(THREE.MathUtils.radToDeg(euler.y));
}

// 수평 방향 벡터를 Y축 yaw 각도(도)로 변환한다.
export function yawDegreesFromDirection(direction) {
  return normalizeRotationDegrees(
    THREE.MathUtils.radToDeg(Math.atan2(direction.x, direction.z)),
  );
}

// 디버그 배지에 표시할 "카메라가 어느 방향을 보고 있는지" 문자열을 만든다.
export function formatCameraViewAngle(camera) {
  const direction = camera.getWorldDirection(new THREE.Vector3());
  const yaw = yawDegreesFromDirection(direction);
  const pitch = Math.round(
    THREE.MathUtils.radToDeg(
      Math.asin(THREE.MathUtils.clamp(direction.y, -1, 1)),
    ),
  );

  return `View Yaw ${yaw}째 / Pitch ${pitch}째`;
}

// 교체(Replace) 가능한 오브젝트인지 판단한다: 이동 가능한 일반 가구이거나, 문/창문이면 된다.
export function isReplaceableObject(object) {
  if (!object) return false;

  return (
    canTransformObject(object) ||
    object.userData.sourceType === "door" ||
    object.userData.sourceType === "window"
  );
}

// 문/창문 GLB 템플릿을 못 찾았을 때 대신 보여줄 단색 박스를 만든다.
export function createFallbackReferenceTemplate(sourceType) {
  const geometry = new THREE.BoxGeometry(1, 1, 1);
  const material = new THREE.MeshStandardMaterial({
    color: sceneColor(
      sourceType === "door" ? "doorReference" : "windowReference",
    ),
    roughness: 0.72,
  });
  const mesh = new THREE.Mesh(geometry, material);
  const group = new THREE.Group();

  group.add(mesh);
  return group;
}
