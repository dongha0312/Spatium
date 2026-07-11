import * as THREE from "three";
import { optionalConfigBoolean, wallConfigNumber } from "./sceneConfig";

const WALL_PARALLEL_RELAXATION = 0;
const WALL_ALIGNMENT_RELAXATION_ANGLE = Math.PI / 4;
const WALL_SLIDE_CONTACT_DISTANCE = 0.08;
const WALL_MOVEMENT_MARGIN = 1e-4;
// 드래그 한 이벤트당 스윕 스텝 수 상한. 가구가 벽에 막힌 채 커서만 멀리 나가면 요청
// 이동량(커서 목표 - 현재 위치)이 수 미터로 커져 스텝 수가 폭증하는 것을 막는다.
// 상한을 넘는 이동분은 다음 pointermove에서 현재 위치 기준으로 다시 계산되므로 잘라도 된다.
const SWEEP_MAX_STEPS = 32;
// broad-phase 스윕 AABB에 더하는 기본 여유. 스텝 크기/경계 epsilon보다 충분히 커서,
// 후보에서 빠진 벽이 이번 이벤트의 이동 범위 안에서 충돌할 수 없음을 보장한다.
const SWEEP_BROADPHASE_MARGIN = 0.3;

// 아래 재사용 벡터들은 충돌 판정 핫패스(드래그 중 스텝×벽 수만큼 호출)에서 호출마다
// Vector3를 새로 만들지 않기 위한 모듈 스코프 임시 객체다. 각 함수는 자기 전용 temp만
// 쓰고 결과를 스칼라나 즉시 소비되는 값으로 반환하므로, 호출이 중첩되어도 안전하다.
const projectionBasisX = new THREE.Vector3();
const projectionBasisY = new THREE.Vector3();
const projectionBasisZ = new THREE.Vector3();
const faceAngleNormal = new THREE.Vector3();
const faceAngleBasisX = new THREE.Vector3();
const faceAngleBasisY = new THREE.Vector3();
const faceAngleBasisZ = new THREE.Vector3();
const polygonBasisX = new THREE.Vector3();
const polygonBasisY = new THREE.Vector3();
const polygonBasisZ = new THREE.Vector3();
const polygonCorner = new THREE.Vector3();
const solidBasisX = new THREE.Vector3();
const solidBasisY = new THREE.Vector3();
const solidBasisZ = new THREE.Vector3();
const solidOffset = new THREE.Vector3();
const sweepAabb = new THREE.Box3();
const sweepShiftedMin = new THREE.Vector3();
const sweepShiftedMax = new THREE.Vector3();

// OBB를 감싸는 월드 축 정렬 AABB를 구한다. Matrix3는 column-major이므로
// elements[j*3+i]가 j번째 기저축의 i번째 성분이다.
function obbWorldAabb(obb, target) {
  const e = obb.rotation.elements;
  const hx = obb.halfSize.x;
  const hy = obb.halfSize.y;
  const hz = obb.halfSize.z;
  const ex = Math.abs(e[0]) * hx + Math.abs(e[3]) * hy + Math.abs(e[6]) * hz;
  const ey = Math.abs(e[1]) * hx + Math.abs(e[4]) * hy + Math.abs(e[7]) * hz;
  const ez = Math.abs(e[2]) * hx + Math.abs(e[5]) * hy + Math.abs(e[8]) * hz;
  target.min.set(obb.center.x - ex, obb.center.y - ey, obb.center.z - ez);
  target.max.set(obb.center.x + ex, obb.center.y + ey, obb.center.z + ez);
  return target;
}

// 콜라이더의 월드 AABB(broad-phase용). 벽 콜라이더는 정적이고, 문/창문 콜라이더도
// 캐시된 목록이 유지되는 동안은 움직이지 않으므로 첫 계산 후 콜라이더 객체에 저장한다.
// 콜라이더가 재생성되는 시점(벽으로 메우기, activeColliders 캐시 무효화)에는 객체 자체가
// 새로 만들어지므로 따로 무효화할 필요가 없다.
function colliderWorldAabb(wall) {
  if (!wall.worldAabb) {
    wall.worldAabb = obbWorldAabb(wall.obb, new THREE.Box3());
  }
  return wall.worldAabb;
}

// broad-phase: 오브젝트 OBB의 AABB를 이동 벡터와 여유(margin)만큼 확장한 "스윕 영역"과
// 겹치는 콜라이더만 추려낸다. 멀리 있는 벽들은 AABB 비교 한 번으로 탈락하므로,
// 스텝 루프의 정밀 판정(다각형 투영/SAT) 대상이 근처 벽 몇 개로 줄어든다.
function collidersNearSweep(objectObb, movement, wallColliders, margin) {
  obbWorldAabb(objectObb, sweepAabb);
  sweepShiftedMin.copy(sweepAabb.min).add(movement);
  sweepShiftedMax.copy(sweepAabb.max).add(movement);
  sweepAabb.expandByPoint(sweepShiftedMin);
  sweepAabb.expandByPoint(sweepShiftedMax);
  sweepAabb.expandByScalar(margin);

  return wallColliders.filter((wall) =>
    sweepAabb.intersectsBox(colliderWorldAabb(wall)),
  );
}

// 벡터를 콘솔 디버그 로그용으로 짧게 반올림한다.
function vectorSummary(vector) {
  return {
    x: Number(vector.x.toFixed(4)),
    y: Number(vector.y.toFixed(4)),
    z: Number(vector.z.toFixed(4)),
  };
}

// 어떤 벽이 이동을 막았는지 콘솔에서 알아보기 쉽게 요약한다.
function wallDebugSummary(wall) {
  return {
    wallObject: wall.object?.name || "(unnamed wall)",
    triangleStart: wall.triangleStart,
    triangleCount: wall.triangleCount,
    roomFacingNormal: wall.roomFacingNormal
      ? vectorSummary(wall.roomFacingNormal)
      : null,
    roomFacingProjection: wall.roomFacingProjection,
  };
}

function shouldLogWallDiagnostics() {
  // 드래그 중 pointermove마다 console.debug가 찍히면(DevTools가 열려 있을 때 특히)
  // 그 자체가 큰 비용이라 기본값은 끔. 필요하면 scene config에서 켠다.
  return optionalConfigBoolean(
    ["wallConstraints", "logWallDiagnostics"],
    false,
  );
}

// 디버그 로그용 표시 이름 (예: "chair 2").
export function editableObjectLabel(object) {
  const item = object.userData.roomItem;
  return `${item.category || object.userData.category || "object"} ${object.userData.sourceIndex + 1
    }`;
}

// 이동/회전 가능한 일반 가구인지 판단한다 (문/창문은 editable:false).
export function canTransformObject(object) {
  return Boolean(object?.userData.editable);
}

// 오브젝트의 local OBB(생성 시 계산해둔 충돌 박스)를 현재 matrixWorld로 변환해
// 월드 좌표계 OBB로 만든다. 충돌 판정은 전부 이 world OBB 기준으로 이뤄진다.
export function worldObbForObject(object) {
  object.updateWorldMatrix(true, false);
  return object.userData.localObb.clone().applyMatrix4(object.matrixWorld);
}

// 문/창문을 가구 이동 시 부딪히는 고정 장애물로 취급하기 위한 콜라이더.
// spanAxes/roomFacingNormal이 없으므로 wallBlocksObjectObb는 OBB 교차 여부만으로 판정한다.
export function referenceCollidersFromRoots(referenceRoots) {
  return (referenceRoots || [])
    .filter((root) => root?.userData?.localObb)
    .map((root) => ({
      object: root,
      obb: worldObbForObject(root),
      spanAxes: null,
      roomFacingNormal: null,
      roomFacingProjection: null,
    }));
}

// 지금의 position/quaternion/scale을 "마지막으로 유효했던 상태"로 기억해둔다.
// 회전/높이 조정이 벽과 충돌하면 이 값으로 되돌린다(restoreValidTransform).
export function rememberValidTransform(object) {
  if (!object) return;

  if (!object.userData.lastValidPosition) {
    object.userData.lastValidPosition = object.position.clone();
    object.userData.lastValidQuaternion = object.quaternion.clone();
    object.userData.lastValidScale = object.scale.clone();
    return;
  }

  object.userData.lastValidPosition.copy(object.position);
  object.userData.lastValidQuaternion.copy(object.quaternion);
  object.userData.lastValidScale.copy(object.scale);
}

// rememberValidTransform으로 저장해둔 마지막 유효 transform으로 되돌린다.
export function restoreValidTransform(object) {
  if (!object?.userData.lastValidPosition) return;

  object.position.copy(object.userData.lastValidPosition);
  object.quaternion.copy(object.userData.lastValidQuaternion);
  object.scale.copy(object.userData.lastValidScale);
  object.updateWorldMatrix(true, false);
}

// 이 오브젝트 자체가 "벽을 넘으면 안 되는" 제약 대상인지 판단한다.
// 일반 가구만 해당하고, 문/창문과 ignoreWallConstraint 플래그가 켜진 것은 제외한다.
export function shouldConstrainToWalls(object) {
  const category =
    object?.userData.roomItem?.category || object?.userData.category;
  return Boolean(
    object?.userData.editable &&
    !object.userData.ignoreWallConstraint &&
    category !== "door" &&
    category !== "window",
  );
}

// 오브젝트가 벽 콜라이더(문/창문 포함) 중 하나라도 막고 있으면 true.
export function objectIntersectsWalls(object, wallColliders) {
  if (!object || !wallColliders.length) return false;

  const objectObb = worldObbForObject(object);
  return wallColliders.some((wall) => wallBlocksObjectObb(objectObb, wall));
}

// objectIntersectsWalls와 같은 판정이지만, 막고 있는 벽 콜라이더 목록 전체를 반환한다.
export function getIntersectingWalls(object, wallColliders) {
  if (!object || !wallColliders.length) return [];

  const objectObb = worldObbForObject(object);
  return wallColliders.filter((wall) => wallBlocksObjectObb(objectObb, wall));
}

// OBB를 주어진 축(axis)에 투영했을 때의 "반지름"(중심에서 투영된 경계까지 거리)을 구한다.
// SAT(분리축 정리) 기반 충돌 판정의 기본 연산.
export function projectionRadiusForObb(obb, axis) {
  obb.rotation.extractBasis(
    projectionBasisX,
    projectionBasisY,
    projectionBasisZ,
  );

  return (
    Math.abs(axis.dot(projectionBasisX)) * obb.halfSize.x +
    Math.abs(axis.dot(projectionBasisY)) * obb.halfSize.y +
    Math.abs(axis.dot(projectionBasisZ)) * obb.halfSize.z
  );
}

// 오브젝트의 면(가장 잘 정렬된 축)이 벽 법선과 이루는 각도. 가구가 벽에 딱 붙어 나란히
// 있는지(각도 작음), 비스듬히 걸쳐 있는지(각도 큼) 판단하는 데 쓰인다.
export function objectWallFaceNormalAngle(objectObb, wall) {
  if (!wall.roomFacingNormal) return Math.PI / 2;

  faceAngleNormal.copy(wall.roomFacingNormal).normalize();
  objectObb.rotation.extractBasis(
    faceAngleBasisX,
    faceAngleBasisY,
    faceAngleBasisZ,
  );

  const bestAlignment = Math.max(
    Math.abs(faceAngleBasisX.normalize().dot(faceAngleNormal)),
    Math.abs(faceAngleBasisY.normalize().dot(faceAngleNormal)),
    Math.abs(faceAngleBasisZ.normalize().dot(faceAngleNormal)),
  );

  return Math.acos(THREE.MathUtils.clamp(bestAlignment, -1, 1));
}

// 벽 경계 판정에 쓸 여유값(epsilon)을 계산한다. 가구가 벽과 거의 평행하면 여유를 더 줘서
// (WALL_PARALLEL_RELAXATION) 살짝 걸쳐도 막히지 않게 한다.
export function wallBoundaryEpsilonForObjectAngle(objectObb, wall) {
  const baseEpsilon = wallConfigNumber("boundaryEpsilon");
  const faceNormalAngle = objectWallFaceNormalAngle(objectObb, wall);
  const parallelWeight =
    1 -
    THREE.MathUtils.clamp(
      faceNormalAngle / WALL_ALIGNMENT_RELAXATION_ANGLE,
      0,
      1,
    );

  return baseEpsilon + parallelWeight * WALL_PARALLEL_RELAXATION;
}

// wall.spanAxes에서 이름("height"/"length")으로 축을 찾는다. 이름이 없으면 순서(index)로 fallback.
function spanAxisByName(wall, name, fallbackIndex) {
  return (
    wall.spanAxes?.find((spanAxis) => spanAxis.name === name) ||
    wall.spanAxes?.[fallbackIndex]
  );
}

// 2D 외적 부호 — convexHull2D에서 좌회전/우회전 판정에 사용.
function cross2D(a, b, c) {
  return (
    (b.length - a.length) * (c.height - a.height) -
    (b.height - a.height) * (c.length - a.length)
  );
}

// 2D 점 집합의 볼록 껍질(convex hull)을 구한다 (Andrew's monotone chain 알고리즘).
// 벽 face의 span polygon과 가구를 벽 평면에 투영한 다각형이 겹치는지 검사할 때 쓰인다.
function convexHull2D(points) {
  const sortedPoints = [...points].sort((a, b) =>
    a.length === b.length ? a.height - b.height : a.length - b.length,
  );
  const uniquePoints = sortedPoints.filter(
    (point, index) =>
      index === 0 ||
      Math.abs(point.length - sortedPoints[index - 1].length) > 1e-8 ||
      Math.abs(point.height - sortedPoints[index - 1].height) > 1e-8,
  );

  if (uniquePoints.length <= 2) return uniquePoints;

  const lower = [];
  uniquePoints.forEach((point) => {
    while (
      lower.length >= 2 &&
      cross2D(lower[lower.length - 2], lower[lower.length - 1], point) <= 1e-10
    ) {
      lower.pop();
    }
    lower.push(point);
  });

  const upper = [];
  [...uniquePoints].reverse().forEach((point) => {
    while (
      upper.length >= 2 &&
      cross2D(upper[upper.length - 2], upper[upper.length - 1], point) <= 1e-10
    ) {
      upper.pop();
    }
    upper.push(point);
  });

  lower.pop();
  upper.pop();

  return [...lower, ...upper];
}

// 오브젝트 OBB의 8개 꼭짓점을 벽 평면(heightAxis/lengthAxis 2D 좌표계)에 투영해서
// 2D 다각형(convex hull)을 만든다.
function projectedObbPolygon2D(objectObb, heightAxis, lengthAxis) {
  objectObb.rotation.extractBasis(polygonBasisX, polygonBasisY, polygonBasisZ);

  const projectedCorners = [];
  [-1, 1].forEach((xSign) => {
    [-1, 1].forEach((ySign) => {
      [-1, 1].forEach((zSign) => {
        polygonCorner
          .copy(objectObb.center)
          .addScaledVector(polygonBasisX, objectObb.halfSize.x * xSign)
          .addScaledVector(polygonBasisY, objectObb.halfSize.y * ySign)
          .addScaledVector(polygonBasisZ, objectObb.halfSize.z * zSign);

        projectedCorners.push({
          height: polygonCorner.dot(heightAxis),
          length: polygonCorner.dot(lengthAxis),
        });
      });
    });
  });

  return convexHull2D(projectedCorners);
}

// 2D 다각형을 한 축에 투영했을 때의 min/max 범위 (다각형 간 SAT 충돌 판정용).
function polygonProjectionRange2D(polygon, axis) {
  let min = Infinity;
  let max = -Infinity;

  polygon.forEach((point) => {
    const projected = point.length * axis.length + point.height * axis.height;
    min = Math.min(min, projected);
    max = Math.max(max, projected);
  });

  return { min, max };
}

// 두 2D 볼록다각형이 겹치는지 SAT(분리축 정리)로 판정한다 — 두 다각형의 모든 변을
// 분리축 후보로 시도해서, 하나라도 완전히 분리되면 겹치지 않는다고 본다.
function polygonsOverlap2D(firstPolygon, secondPolygon) {
  if (firstPolygon.length < 3 || secondPolygon.length < 3) {
    return false;
  }

  const polygons = [firstPolygon, secondPolygon];
  for (const polygon of polygons) {
    for (let index = 0; index < polygon.length; index += 1) {
      const nextIndex = (index + 1) % polygon.length;
      const dx = polygon[nextIndex].length - polygon[index].length;
      const dy = polygon[nextIndex].height - polygon[index].height;
      const axis = { length: -dy, height: dx };
      const firstRange = polygonProjectionRange2D(firstPolygon, axis);
      const secondRange = polygonProjectionRange2D(secondPolygon, axis);

      if (firstRange.max < secondRange.min || secondRange.max < firstRange.min) {
        return false;
      }
    }
  }

  return true;
}

// 벽에 spanPolygon(정확한 face 외곽선) 정보가 있으면, 그 다각형과 가구를 벽 평면에
// 투영한 다각형이 겹치는지로 span overlap을 정밀 판정한다. 없으면 null(호출부가 다른 방식으로 판정).
function objectOverlapsWallSpanPolygon(objectObb, wall) {
  if (!wall.spanPolygon?.length) return null;

  const heightSpan = spanAxisByName(wall, "height", 0);
  const lengthSpan = spanAxisByName(wall, "length", 1);
  if (!heightSpan?.axis || !lengthSpan?.axis) return null;

  const objectPolygon = projectedObbPolygon2D(
    objectObb,
    heightSpan.axis,
    lengthSpan.axis,
  );

  return polygonsOverlap2D(objectPolygon, wall.spanPolygon);
}

// 가구가 벽의 길이/높이 범위("span") 안에 있는지 판정한다. 즉 벽과 같은 평면 위에서
// 겹치는 위치에 있는지 — 벽 두께 방향(안/밖)은 별도로(objectObbViolatesWallBoundary 등) 검사한다.
// spanAxes가 없는 콜라이더(예: 문/창문)는 항상 true(범위 제한 없음)를 반환한다.
export function objectOverlapsWallSpan(objectObb, wall) {
  if (!wall.spanAxes?.length) return true;

  const polygonOverlap = objectOverlapsWallSpanPolygon(objectObb, wall);
  if (polygonOverlap != null) return polygonOverlap;

  return wall.spanAxes.every(({ axis, halfSize }) => {
    const objectRadius = projectionRadiusForObb(objectObb, axis);
    const objectProjection = objectObb.center.dot(axis);
    const wallProjection = wall.obb.center.dot(axis);

    return (
      Math.abs(objectProjection - wallProjection) <=
      halfSize + objectRadius + wallConfigNumber("boundarySpanPadding")
    );
  });
}

// 가구가 벽의 "방 안쪽 경계선"(roomFacingProjection)을 침범했는지 판정한다.
// 단순 OBB 겹침이 아니라, 벽 안쪽 면을 기준으로 한 판정이라 더 자연스럽게 동작한다.
export function objectObbViolatesWallBoundary(objectObb, wall) {
  if (!wall.roomFacingNormal || !Number.isFinite(wall.roomFacingProjection)) {
    return false;
  }

  if (!objectOverlapsWallSpan(objectObb, wall)) {
    return false;
  }

  const radius = projectionRadiusForObb(objectObb, wall.roomFacingNormal);
  const innerMostProjection =
    objectObb.center.dot(wall.roomFacingNormal) - radius;
  const boundaryEpsilon = wallBoundaryEpsilonForObjectAngle(objectObb, wall);

  return innerMostProjection < wall.roomFacingProjection - boundaryEpsilon;
}

// 벽 경계를 얼마나 침범했는지 그 깊이(양수)를 계산한다. 안 침범했으면 0.
// 초기 로딩 시 벽에 박혀있는 가구를 밀어낼 방향/거리를 구하는 데 쓰인다(wallPushVector).
export function objectWallBoundaryPenetration(objectObb, wall) {
  if (!wall.roomFacingNormal || !Number.isFinite(wall.roomFacingProjection)) {
    return 0;
  }

  if (!objectOverlapsWallSpan(objectObb, wall)) {
    return 0;
  }

  const radius = projectionRadiusForObb(objectObb, wall.roomFacingNormal);
  const innerMostProjection =
    objectObb.center.dot(wall.roomFacingNormal) - radius;
  const boundaryEpsilon = wallBoundaryEpsilonForObjectAngle(objectObb, wall);

  return Math.max(
    0,
    wall.roomFacingProjection - boundaryEpsilon - innerMostProjection,
  );
}

// 벽 경계까지 남은 여유 거리 (음수면 이미 침범한 상태). objectWallBoundaryPenetration의
// 부호 반대 버전으로, "슬라이드 접촉" 판정(objectTouchesWallForSlide)에 쓰인다.
export function objectWallBoundaryClearance(objectObb, wall) {
  if (!wall.roomFacingNormal || !Number.isFinite(wall.roomFacingProjection)) {
    return Infinity;
  }

  if (!objectOverlapsWallSpan(objectObb, wall)) {
    return Infinity;
  }

  const radius = projectionRadiusForObb(objectObb, wall.roomFacingNormal);
  const innerMostProjection =
    objectObb.center.dot(wall.roomFacingNormal) - radius;
  const boundaryEpsilon = wallBoundaryEpsilonForObjectAngle(objectObb, wall);

  return innerMostProjection - (wall.roomFacingProjection - boundaryEpsilon);
}

// 가구가 이 벽에 거의 붙어 있는지(슬라이드 중 접촉) 판정한다. 현재 이 함수 자체는
// 다른 곳에서 직접 호출되지 않고, 향후 "벽을 따라 미끄러지기" 기능 확장을 위해 남아 있다.
export function objectTouchesWallForSlide(objectObb, wall) {
  if (wall.roomFacingNormal && Number.isFinite(wall.roomFacingProjection)) {
    return (
      objectWallBoundaryClearance(objectObb, wall) <=
      WALL_SLIDE_CONTACT_DISTANCE
    );
  }

  return (
    objectOverlapsWallSpan(objectObb, wall) &&
    objectObb.intersectsOBB(wall.obb, wallConfigNumber("collisionEpsilon"))
  );
}

// 오브젝트가 모든 벽 콜라이더 각각을 얼마나 침범했는지 배열로 반환한다.
// (아래 wallBoundaryPenetrationDidNotIncrease와 함께, 현재는 다른 곳에서 호출되지
// 않는 헬퍼 — 침범량이 늘지 않았는지 검증하는 용도로 만들어둔 것으로 보인다.)
export function wallBoundaryPenetrationsForObject(object, wallColliders) {
  if (!object || !wallColliders.length) return [];

  const objectObb = worldObbForObject(object);
  return wallColliders.map((wall) =>
    objectWallBoundaryPenetration(objectObb, wall),
  );
}

// 이전/이후 침범량 배열을 비교해서, 어느 벽도 더 깊이 침범하지 않았으면 true.
export function wallBoundaryPenetrationDidNotIncrease(previous, next) {
  const tolerance = wallConfigNumber("boundaryEpsilon") + 1e-5;

  return next.every(
    (depth, index) => depth <= (previous[index] || 0) + tolerance,
  );
}

// 이 벽(또는 문/창문 콜라이더)이 오브젝트를 막는지 최종 판정한다. roomFacingNormal이
// 있으면 "경계선 침범" 기준, 없으면(문/창문처럼) 단순 OBB 겹침 기준으로 판정한다.
export function wallBlocksObjectObb(objectObb, wall) {
  if (wall.roomFacingNormal && Number.isFinite(wall.roomFacingProjection)) {
    return objectObbViolatesWallBoundary(objectObb, wall);
  }

  return (
    (objectOverlapsWallSpan(objectObb, wall) &&
      objectObb.intersectsOBB(wall.obb, wallConfigNumber("collisionEpsilon"))) ||
    objectObbViolatesWallBoundary(objectObb, wall)
  );
}

// 이 오브젝트에 대해 "벽과 겹치는지" 충돌 표시(빨간 박스 등)를 계산해야 하는지 판단한다.
export function shouldCheckFurnitureCollision(object) {
  const category =
    object?.userData.roomItem?.category || object?.userData.category;
  return Boolean(
    object?.userData.editable && category !== "door" && category !== "window",
  );
}

// 회전/높이 조정 등 "적용 후 되돌릴지 말지"를 결정할 때 쓰는 최종 판정.
// 벽 제약 대상이 아닌 오브젝트(문/창문 자신 등)는 항상 false.
export function hasWallCollision(object, wallColliders) {
  if (!shouldConstrainToWalls(object) || !wallColliders.length) return false;
  return objectIntersectsWalls(object, wallColliders);
}

// 씬 로딩 직후(또는 가구 추가 직후) 벽에 박혀 있는 가구들을 전부 밀어내고, 유효 transform으로 기록한다.
export function initializeWallConstraints(editableObjects, wallColliders) {
  editableObjects.forEach((object) => {
    pushObjectOutOfWalls(object, wallColliders);
    object.userData.startsInWallCollision = false;
    object.userData.ignoreWallConstraint = false;
    rememberValidTransform(object);
  });
}

// 벽을 침범한 오브젝트를 바깥으로 밀어낼 벡터를 계산한다. roomFacingNormal이 있으면 그
// 방향으로 침범 깊이만큼, 없으면 겹침이 가장 작은 축 방향으로 밀어낸다(pushObjectOutOfWalls에서 사용).
function wallPushVector(objectObb, wall) {
  if (wall.roomFacingNormal && Number.isFinite(wall.roomFacingProjection)) {
    const penetration = objectWallBoundaryPenetration(objectObb, wall);
    if (penetration <= 0) return null;

    return wall.roomFacingNormal
      .clone()
      .multiplyScalar(penetration + 1e-3);
  }

  if (
    !objectOverlapsWallSpan(objectObb, wall) ||
    !objectObb.intersectsOBB(wall.obb, wallConfigNumber("collisionEpsilon"))
  ) {
    return null;
  }

  const axisX = new THREE.Vector3();
  const axisY = new THREE.Vector3();
  const axisZ = new THREE.Vector3();
  wall.obb.rotation.extractBasis(axisX, axisY, axisZ);
  const axes = [axisX, axisY, axisZ];
  const halfSizes = [
    wall.obb.halfSize.x,
    wall.obb.halfSize.y,
    wall.obb.halfSize.z,
  ];

  let bestOverlap = Infinity;
  let bestAxis = null;
  let bestSign = 1;

  for (let i = 0; i < 3; i += 1) {
    const axis = axes[i].normalize();
    const objRadius = projectionRadiusForObb(objectObb, axis);
    const wallRadius = halfSizes[i];
    const diff =
      objectObb.center.dot(axis) - wall.obb.center.dot(axis);
    const overlap = objRadius + wallRadius - Math.abs(diff);

    if (overlap <= 0) return null;
    if (overlap < bestOverlap) {
      bestOverlap = overlap;
      bestAxis = axis;
      bestSign = diff >= 0 ? 1 : -1;
    }
  }

  if (!bestAxis) return null;
  return bestAxis.clone().multiplyScalar(bestSign * (bestOverlap + 1e-3));
}

// 오브젝트가 벽과 안 겹칠 때까지 반복적으로(최대 10회) 밀어낸다.
function pushObjectOutOfWalls(object, wallColliders) {
  for (let iteration = 0; iteration < 10; iteration += 1) {
    object.updateWorldMatrix(true, false);
    const objectObb = worldObbForObject(object);
    const push = new THREE.Vector3();
    let collisionFound = false;

    wallColliders.forEach((wall) => {
      if (!wallBlocksObjectObb(objectObb, wall)) return;
      collisionFound = true;

      const v = wallPushVector(objectObb, wall);
      if (v) push.add(v);
    });

    if (!collisionFound) return;
    object.position.add(push);
  }

  object.updateWorldMatrix(true, false);
}

// roomFacingNormal이 없는 벽(또는 문/창문)에 대해, 벽의 가장 얇은 축(두께 방향)을 찾아
// 그 방향으로 오브젝트까지 남은 여유 거리를 계산한다 ("solid" 충돌 판정의 기반).
// 반환하는 normal은 모듈 스코프 재사용 벡터라서, 호출 측은 다음 wallSolidClearance
// 호출 전에 값을 소비해야 한다(현재 호출부는 모두 즉시 사용).
function wallSolidClearance(objectObb, wall) {
  const hx = wall.obb.halfSize.x;
  const hy = wall.obb.halfSize.y;
  const hz = wall.obb.halfSize.z;

  wall.obb.rotation.extractBasis(solidBasisX, solidBasisY, solidBasisZ);

  let axis;
  let thicknessHalfSize;
  if (hx <= hy && hx <= hz) {
    axis = solidBasisX;
    thicknessHalfSize = hx;
  } else if (hy <= hz) {
    axis = solidBasisY;
    thicknessHalfSize = hy;
  } else {
    axis = solidBasisZ;
    thicknessHalfSize = hz;
  }

  axis.normalize();
  solidOffset.copy(objectObb.center).sub(wall.obb.center);
  const normal = axis.multiplyScalar(solidOffset.dot(axis) >= 0 ? 1 : -1);
  const objectRadius = projectionRadiusForObb(objectObb, normal);
  const clearance =
    Math.abs(solidOffset.dot(axis)) - thicknessHalfSize - objectRadius;

  return { normal, clearance };
}

// 요청된 이동(movement)을, 벽을 넘지 않는 선까지만 허용하도록 축소한다.
// 1차 패스: roomFacingNormal이 있는 벽의 "경계선"을 넘는 성분을 제거.
// 2차 패스: 그래도 남은 solid 콜라이더(문/창문 등, roomFacingNormal 없는 벽) 겹침을 제거.
// 두 패스를 번갈아 최대 4번 반복해서 여러 벽이 동시에 막는 경우(모서리 등)도 처리한다.
function adjustedMovementForObbBeforeWallCollision(
  objectObb,
  movement,
  wallColliders,
  onBlockedWall = null,
) {
  if (!objectObb || !wallColliders.length || movement.lengthSq() <= 1e-10) {
    return movement.clone();
  }

  const adjusted = movement.clone();
  // 스텝×벽 수만큼 OBB를 clone하지 않도록, 함수당 하나만 만들어 copy로 재사용한다.
  const movedObb = objectObb.clone();

  for (let pass = 0; pass < 4; pass += 1) {
    let changed = false;

    wallColliders.forEach((wall) => {
      if (!wall.roomFacingNormal || !Number.isFinite(wall.roomFacingProjection)) {
        return;
      }

      movedObb.copy(objectObb);
      movedObb.center.add(adjusted);
      if (!objectOverlapsWallSpan(movedObb, wall)) return;

      const normalDistance = adjusted.dot(wall.roomFacingNormal);
      if (normalDistance >= -1e-10) return;

      const radius = projectionRadiusForObb(objectObb, wall.roomFacingNormal);
      const innerMostProjection =
        objectObb.center.dot(wall.roomFacingNormal) - radius;
      const boundaryProjection =
        wall.roomFacingProjection -
        wallBoundaryEpsilonForObjectAngle(objectObb, wall);
      const clearance = innerMostProjection - boundaryProjection;
      const allowedInwardDistance = Math.max(
        0,
        clearance - WALL_MOVEMENT_MARGIN,
      );
      const blockedInwardDistance =
        -normalDistance - allowedInwardDistance;

      if (blockedInwardDistance > 1e-10) {
        onBlockedWall?.(wall, {
          type: "boundary",
          clearance,
          requestedInwardDistance: -normalDistance,
          blockedInwardDistance,
        });
        adjusted.addScaledVector(
          wall.roomFacingNormal,
          blockedInwardDistance,
        );
        changed = true;
      }
    });

    wallColliders.forEach((wall) => {
      movedObb.copy(objectObb);
      movedObb.center.add(adjusted);
      if (!objectOverlapsWallSpan(movedObb, wall)) return;
      if (
        !movedObb.intersectsOBB(
          wall.obb,
          wallConfigNumber("collisionEpsilon"),
        )
      ) {
        return;
      }

      const { normal, clearance } = wallSolidClearance(objectObb, wall);
      const normalDistance = adjusted.dot(normal);
      if (normalDistance >= -1e-10) return;

      const allowedInwardDistance = Math.max(
        0,
        clearance - WALL_MOVEMENT_MARGIN,
      );
      const blockedInwardDistance =
        -normalDistance - allowedInwardDistance;

      if (blockedInwardDistance > 1e-10) {
        onBlockedWall?.(wall, {
          type: "solid",
          clearance,
          normal: vectorSummary(normal),
          requestedInwardDistance: -normalDistance,
          blockedInwardDistance,
        });
        adjusted.addScaledVector(normal, blockedInwardDistance);
        changed = true;
      }
    });

    if (!changed) break;
  }

  return adjusted;
}

// 드래그로 가구를 옮길 때 호출되는 진입점. 큰 이동을 작은 step으로 쪼개서(sweepStep 기준)
// 각 step마다 adjustedMovementForObbBeforeWallCollision으로 벽 충돌을 검사한다.
// 이렇게 하면 빠르게 드래그해도 가구가 벽을 순간적으로 통과하는 것을 막을 수 있다.
export function constrainedMovementBeforeWallCollision(
  object,
  movement,
  wallColliders,
) {
  if (!object || !wallColliders.length || movement.lengthSq() <= 1e-10) {
    return movement.clone();
  }

  const totalDistance = movement.length();
  const stepSize = Math.max(
    0.005,
    Math.min(
      wallConfigNumber("sweepStep"),
      wallConfigNumber("colliderHalfThickness") * 2,
    ),
  );
  const objectObb = worldObbForObject(object);
  const blockedWalls = [];
  const blockedWallSet = new Set();

  object.userData.blockedWallColliders = blockedWalls;

  // broad-phase: 이번 이동의 스윕 영역과 겹치는 콜라이더만 정밀 검사한다.
  // 후보가 하나도 없으면(빈 공간 드래그) 스텝 루프 없이 요청 이동을 그대로 허용한다.
  const broadphaseMargin =
    Math.max(SWEEP_BROADPHASE_MARGIN, stepSize * 2) +
    wallConfigNumber("boundaryEpsilon") +
    wallConfigNumber("boundarySpanPadding");
  const nearbyColliders = collidersNearSweep(
    objectObb,
    movement,
    wallColliders,
    broadphaseMargin,
  );

  if (!nearbyColliders.length) {
    return movement.clone();
  }

  // 스텝 수 상한. 상한을 넘는 요청(벽에 막힌 채 커서만 멀리 나간 경우)은 이동량 자체를
  // 상한 거리로 잘라서, 스텝 크기(터널링 방지 기준)는 유지한 채 스텝 수만 제한한다.
  const maxDistance = stepSize * SWEEP_MAX_STEPS;
  const clampScale =
    totalDistance > maxDistance ? maxDistance / totalDistance : 1;
  const stepCount = Math.max(
    1,
    Math.ceil((totalDistance * clampScale) / stepSize),
  );
  const requestedStep = movement.clone().multiplyScalar(clampScale / stepCount);
  const constrained = new THREE.Vector3();

  const rememberBlockedWall = (wall, details) => {
    if (blockedWallSet.has(wall)) return;

    blockedWallSet.add(wall);
    blockedWalls.push(wall);
    if (shouldLogWallDiagnostics()) {
      console.debug("[roomSceneEditor] wall movement blocked", {
        object: editableObjectLabel(object),
        ...wallDebugSummary(wall),
        ...details,
      });
    }
  };

  for (let step = 0; step < stepCount; step += 1) {
    const adjustedStep = adjustedMovementForObbBeforeWallCollision(
      objectObb,
      requestedStep,
      nearbyColliders,
      rememberBlockedWall,
    );

    if (adjustedStep.lengthSq() <= 1e-10) break;

    objectObb.center.add(adjustedStep);
    constrained.add(adjustedStep);
  }

  return constrained;
}

// 가구 하나의 mesh 색상/edge 표시를 현재 상태(선택 여부, 충돌 여부)에 맞게 갱신한다.
export function setFurnitureVisualState(object, selectedObject) {
  const isSelected = object === selectedObject;
  // 꺼져 있으면 충돌 여부와 무관하게 항상 기본/선택 색상만 쓴다(선택 시 노란 박스).
  const showCollisionHighlight = optionalConfigBoolean(
    ["wallConstraints", "showCollisionHighlight"],
    true,
  );
  const hasCollision =
    showCollisionHighlight && (object.userData.collisions || []).length > 0;
  const mesh = object.userData.visualMesh;
  const edge = object.userData.edgeLine;

  if (mesh?.material) {
    mesh.material.color.copy(
      hasCollision
        ? object.userData.collisionFillColor
        : object.userData.baseColor,
    );
    mesh.material.opacity = hasCollision ? 0.62 : 0.72;
  }

  if (edge?.material) {
    edge.visible = hasCollision || isSelected;
    edge.renderOrder = 32;
    edge.material.depthTest = false;
    edge.material.depthWrite = false;
    edge.material.color.copy(
      hasCollision
        ? object.userData.collisionColor
        : isSelected
          ? object.userData.selectedEdgeColor
          : object.userData.baseEdgeColor,
    );
    edge.material.opacity = hasCollision || isSelected ? 0.95 : 0.5;
  }
}

// 모든 가구의 벽 충돌 상태를 다시 계산하고(userData.collisions), 시각 표시까지 갱신한다.
// 선택/이동/회전 등 씬이 바뀔 때마다 syncSceneState에서 호출된다.
export function refreshCollisionState(
  editableObjects,
  selectedObject,
  wallColliders = [],
) {
  editableObjects.forEach((object) => {
    object.userData.collisions = [];
    object.userData.intersectingWallColliders = [];
  });

  editableObjects.forEach((object) => {
    if (!shouldCheckFurnitureCollision(object)) return;

    const intersectingWalls = getIntersectingWalls(object, wallColliders);
    object.userData.intersectingWallColliders = intersectingWalls;

    if (intersectingWalls.length) {
      if (object === selectedObject && shouldLogWallDiagnostics()) {
        console.debug("[roomSceneEditor] furniture wall collision", {
          object: editableObjectLabel(object),
          walls: intersectingWalls.map(wallDebugSummary),
        });
      }
      object.userData.collisions.push("wall");
    }
  });

  editableObjects.forEach((object) =>
    setFurnitureVisualState(object, selectedObject),
  );
  return selectedObject?.userData.collisions || [];
}
