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

// 실내 가구 치수(한 변)로 말이 되는 상한. 스캔/카탈로그에서 나오는 가장 큰 가구도
// 6m를 넘지 않는다(크기 슬라이더 상한도 5m). 이걸 넘으면 단위 오류(cm/mm)거나
// 오염된 저장 데이터다.
const MAX_FURNITURE_DIMENSION = 8; // meters

// 가구 dimensions를 정규화한다 (없거나 0이면 기본값, 최소 4cm는 보장).
// 세 축 모두 정상 범위를 벗어나면 m/cm/mm 순으로 단위를 추정해 변환한다 — 카탈로그나
// 저장 데이터에 mm 단위 치수(예: 900×450×1800)가 섞여 들어와 가구가 수백 m로 렌더링되는
// 사고를 막는다. 어떤 단위로도 설명이 안 되는 값(진짜 오염)은 상한으로 잘라낸다.
export function normalizedDimensions(dimensions = {}) {
  const rawX = Number(dimensions.x) || DEFAULT_FURNITURE_DIMENSIONS.x;
  const rawY = Number(dimensions.y) || DEFAULT_FURNITURE_DIMENSIONS.y;
  const rawZ = Number(dimensions.z) || DEFAULT_FURNITURE_DIMENSIONS.z;

  const unitFactor = [1, 0.01, 0.001].find((factor) =>
    [rawX, rawY, rawZ].every(
      (value) =>
        !Number.isFinite(value) ||
        Math.abs(value) * factor <= MAX_FURNITURE_DIMENSION,
    ),
  );
  if (unitFactor === undefined || unitFactor !== 1) {
    console.warn(
      "[roomSceneEditor] Suspicious furniture dimensions:",
      { x: rawX, y: rawY, z: rawZ },
      unitFactor
        ? `interpreted with unit factor ${unitFactor}`
        : "clamped (no unit interpretation fits)",
    );
  }
  const factor = unitFactor ?? 1;

  const sanitize = (value, fallback) => {
    const scaled = Number.isFinite(value) ? Math.abs(value) * factor : fallback;
    return THREE.MathUtils.clamp(
      scaled || fallback,
      0.04,
      MAX_FURNITURE_DIMENSION,
    );
  };

  return {
    x: sanitize(rawX, DEFAULT_FURNITURE_DIMENSIONS.x),
    y: sanitize(rawY, DEFAULT_FURNITURE_DIMENSIONS.y),
    z: sanitize(rawZ, DEFAULT_FURNITURE_DIMENSIONS.z),
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

// metadata에 저장된 가구 하나의 y값이 실제 방 바닥 높이와 이 이상 어긋나면(오염된 저장
// 데이터 등) 신뢰하지 않는다. 예: 예전 버전 버그로 특정 가구가 바닥에서 수 미터 떨어진
// 채 저장된 경우, 그 값을 기준으로 삼으면 그 이후 추가되는 모든 가구가 같이 떠버린다.
const FLOOR_Y_MISMATCH_TOLERANCE = 0.5; // meters

// 방의 바닥 Y좌표를 추정한다. metadata에 저장된 가구들의 (위치 - 높이/2) 중 최솟값을
// 우선 쓰되, roomFloorY(호출자가 넘겨주는, 실제 바닥 mesh 기준의 신뢰할 수 있는 높이)와
// 너무 어긋나면(오염된 데이터로 보고) roomFloorY로 대체한다. 가구가 하나도 없으면
// 처음부터 roomFloorY를 쓴다.
// roomFloorY는 방 전체 bounding box의 최저점이 아니라 calculateRoomMeasurements()가
// 고른 "가장 넓은 바닥 면적 그룹"의 높이여야 한다 — 방 모델에 섞여 들어간 작은 오염된
// mesh(과거 버그로 잘못 저장된 벽 메움 등) 하나가 전체 bounding box를 끌어내리는 것을
// 막기 위함이다.
export function estimateFloorY(metadataObjects, roomFloorY) {
  const hasRoomFloorY = Number.isFinite(roomFloorY);
  const objectFloorYs = (metadataObjects || [])
    .map((item) => {
      const y = Number(item.transform?.columns?.[3]?.[1]);
      const height = Number(item.dimensions?.y);
      return Number.isFinite(y) && Number.isFinite(height)
        ? y - height / 2
        : null;
    })
    .filter((value) => value != null);

  if (!objectFloorYs.length) {
    return hasRoomFloorY ? roomFloorY : 0;
  }

  const candidateFloorY = Math.min(...objectFloorYs);
  if (
    hasRoomFloorY &&
    Math.abs(candidateFloorY - roomFloorY) > FLOOR_Y_MISMATCH_TOLERANCE
  ) {
    return roomFloorY;
  }

  return candidateFloorY;
}

// 저장된 가구 위치가 방 바닥 경계에서 이 이상 벗어나 있으면(오염된 transform)
// 신뢰하지 않는다. 방 밖으로 살짝 걸치는 정상 케이스(내닫이창 앞 가구, 스캔 오차)는
// 허용해야 하므로 여유를 둔다.
const OUT_OF_ROOM_XZ_MARGIN = 2; // meters
// 바닥에서 이 이상 떠 있는 가구는 오염된 것으로 본다.
const OUT_OF_ROOM_MAX_ABOVE_FLOOR = 10; // meters
// 가구 중심이 바닥보다 이 이상 아래면(절반 이상 파묻힘) 오염된 것으로 본다.
// 단차 있는 방(현관/거실 높이 차이)의 낮은 바닥에 놓인 가구는 허용해야 하므로
// 0으로 두지 않는다.
const OUT_OF_ROOM_MAX_BELOW_FLOOR = 0.75; // meters

// 저장된 transform이 오염돼(과거 저장 버그 등) 방 밖 멀리 렌더링되는 가구를 방 안쪽으로
// 되돌린다. 이런 가구는 씬 bounding box를 수백 km로 부풀려 카메라 프레이밍까지 망가뜨리고,
// 사용자가 화면에서 찾을 수도 없다. XZ는 바닥 경계 안쪽으로 클램프하고(방향 정보 최대한
// 보존), Y가 비정상이면 바닥 위에 앉힌다. 되돌린 가구 root 배열을 반환한다(로깅용).
// measurements가 바닥 폴리곤 기준(areaSource === "floor")이 아니면 경계 자체를 신뢰할 수
// 없으므로 아무것도 하지 않는다.
export function recoverOutOfRoomFurniture(objects, measurements, floorY) {
  if (!measurements || measurements.areaSource !== "floor") return [];

  const halfWidth = measurements.width / 2;
  const halfDepth = measurements.depth / 2;
  const center = measurements.center;
  const baseY = Number.isFinite(floorY) ? floorY : center.y;
  const recovered = [];

  objects.forEach((root) => {
    const position = root.position;
    const xzFinite = Number.isFinite(position.x) && Number.isFinite(position.z);
    const xzOutside =
      !xzFinite ||
      Math.abs(position.x - center.x) > halfWidth + OUT_OF_ROOM_XZ_MARGIN ||
      Math.abs(position.z - center.z) > halfDepth + OUT_OF_ROOM_XZ_MARGIN;
    const yOutside =
      !Number.isFinite(position.y) ||
      position.y < baseY - OUT_OF_ROOM_MAX_BELOW_FLOOR ||
      position.y > baseY + OUT_OF_ROOM_MAX_ABOVE_FLOOR;
    if (!xzOutside && !yOutside) return;

    const dimensions = normalizedDimensions(root.userData.roomItem?.dimensions);
    // 가구 절반 폭만큼 안쪽으로 넣어 벽에 반쯤 파묻히지 않게 한다(가구가 방보다 크면
    // 그냥 중앙에 둔다). 최종 벽 겹침 보정은 이후 initializeWallConstraints가 처리한다.
    const insetX = Math.min(dimensions.x / 2, Math.max(halfWidth - 0.05, 0));
    const insetZ = Math.min(dimensions.z / 2, Math.max(halfDepth - 0.05, 0));
    position.set(
      xzFinite
        ? THREE.MathUtils.clamp(
            position.x,
            center.x - halfWidth + insetX,
            center.x + halfWidth - insetX,
          )
        : center.x,
      yOutside ? baseY + dimensions.y / 2 : position.y,
      xzFinite
        ? THREE.MathUtils.clamp(
            position.z,
            center.z - halfDepth + insetZ,
            center.z + halfDepth - insetZ,
          )
        : center.z,
    );
    root.updateWorldMatrix(true, false);
    // 초기화(reset)와 충돌 복원(lastValid)이 오염된 원래 위치로 되돌리지 않게 갱신한다.
    root.userData.initialPosition?.copy(position);
    root.userData.lastValidPosition?.copy(position);
    recovered.push(root);
  });

  return recovered;
}

// 각도를 -180 ~ 180 범위로 정규화한다 (예: 190 -> -170).
export function normalizeRotationDegrees(degrees) {
  const normalized = THREE.MathUtils.euclideanModulo(degrees + 180, 360) - 180;
  return Math.round(normalized);
}

// 오브젝트의 현재 Y축 회전(quaternion)을 -180~180도 정수로 변환한다. roomYawOffsetDegrees를
// 주면 그만큼 뺀 "방 기준 상대 각도"를 돌려준다(estimateRoomYawOffsetDegrees 참고).
export function rotationDegreesFromObject(object, roomYawOffsetDegrees = 0) {
  if (!object) return 0;

  const euler = new THREE.Euler().setFromQuaternion(object.quaternion, "YXZ");
  return normalizeRotationDegrees(
    THREE.MathUtils.radToDeg(euler.y) - roomYawOffsetDegrees,
  );
}

// 방 외곽선(outlineSegments)으로부터 "방이 월드 좌표축에서 얼마나 돌아가 있는지"를
// 추정한다(-45~45도). LiDAR/ARKit 스캔은 중력(Y축)만 정렬하고 좌우(X/Z) 방향은 스캔
// 시작 시점 기기 방향 기준이라, 방의 실제 벽 방향이 월드 축의 0/90/180도와 정확히 안
// 맞을 수 있다. 이 오프셋을 회전 각도 표시/입력에 반영하면 "0/90/180"이 실제로 벽에
// 딱 붙는 각도가 된다.
export function estimateRoomYawOffsetDegrees(outlineSegments) {
  if (!outlineSegments?.length) return 0;

  let sinSum = 0;
  let cosSum = 0;

  outlineSegments.forEach((segment) => {
    const dx = segment.end.x - segment.start.x;
    const dz = segment.end.z - segment.start.z;
    const length = Math.hypot(dx, dz);
    if (length < 1e-6) return;

    // 벽 방향은 90도 주기로만 의미가 있다(반대 방향/수직 벽 모두 같은 정렬 오프셋을
    // 나타냄). 각도를 4배로 만들어(90도 주기 -> 360도 주기) 표준 원형 평균(atan2)을
    // 구한 뒤 다시 4로 나누면, 여러 벽의 방향을 길이 가중 평균낸 "정렬 오프셋"이 나온다.
    const angle = Math.atan2(dx, dz) * 4;
    sinSum += Math.sin(angle) * length;
    cosSum += Math.cos(angle) * length;
  });

  if (!sinSum && !cosSum) return 0;

  return THREE.MathUtils.radToDeg(Math.atan2(sinSum, cosSum) / 4);
}

// 수평 방향 벡터를 Y축 yaw 각도(도)로 변환한다.
export function yawDegreesFromDirection(direction) {
  return normalizeRotationDegrees(
    THREE.MathUtils.radToDeg(Math.atan2(direction.x, direction.z)),
  );
}

// 디버그 배지에 표시할 "카메라가 어느 방향을 보고 있는지" 문자열을 만든다.
// controls(OrbitControls)를 넘기면 타겟까지의 거리(줌 정도)도 함께 표시한다.
export function formatCameraViewAngle(camera, controls) {
  const direction = camera.getWorldDirection(new THREE.Vector3());
  const yaw = yawDegreesFromDirection(direction);
  const pitch = Math.round(
    THREE.MathUtils.radToDeg(
      Math.asin(THREE.MathUtils.clamp(direction.y, -1, 1)),
    ),
  );

  const distanceText = controls
    ? ` / Dist ${controls.getDistance().toFixed(2)}m`
    : "";

  return `View Yaw ${yaw}도 / Pitch ${pitch}도${distanceText}`;
}

// 교체(Replace) 가능한 오브젝트인지 판단한다: 이동 가능한 일반 가구이거나, 문/창문이거나,
// (문/창문을 채워 넣을 수 있는) 개구부 마커면 된다.
export function isReplaceableObject(object) {
  if (!object) return false;

  return (
    canTransformObject(object) ||
    object.userData.sourceType === "door" ||
    object.userData.sourceType === "window" ||
    object.userData.sourceType === "opening"
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
