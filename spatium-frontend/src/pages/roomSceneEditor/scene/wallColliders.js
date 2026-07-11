import * as THREE from "three";
import { OBB } from "three/examples/jsm/math/OBB.js";
import { sceneColor, wallConfigNumber } from "./sceneConfig";

const WALL_FACE_NORMAL_Y_LIMIT = 0.25;
const WALL_FACE_MIN_AREA = 0.000001;
const WALL_FACE_MIN_HEIGHT = 0.05;
const WALL_FACE_MIN_LENGTH = 0.05;
const FLOOR_SIDE_SAMPLE_DISTANCE = 0.12;

// 원본 스캔 mesh 중, 앱이 자체 카탈로그 모델로 대체(replace)한 것들을 이름 패턴으로
// 판별한다. 이런 mesh는 화면에 숨기고(prepareRoomModel) 저장에서도 제외한다(serializeRoomModelToJson).
export function isUsdReplacedMesh(object) {
  let cursor = object;
  while (cursor) {
    if (
      cursor.name === "Object_grp" ||
      /^(Chair|Table|Storage|Sofa|Oven|Refrigerator)_grp$/i.test(cursor.name) ||
      /^(Door|Window)/i.test(cursor.name)
    ) {
      return true;
    }
    cursor = cursor.parent;
  }
  return false;
}

// mesh가 벽인지 판별한다. userData.isUsdWallMesh가 있으면(JSON 복원본 등) 바로 인정하고,
// 없으면 조상 노드 이름이 "Wall_N_grp"/"WallN" 패턴인지로 판단한다. 문/창문 이름 패턴을
// 만나면 즉시 false — 같은 그룹 안에 문/창문 mesh가 같이 있어도 혼동하지 않는다.
export function isUsdWallMesh(object) {
  if (!object.isMesh) return false;
  if (object.userData.isUsdWallMesh) return true;

  let cursor = object;
  let hasWallNode = false;
  while (cursor) {
    const name = cursor.name || "";
    if (/^(Door|Window)\d*/i.test(name)) return false;
    if (/^Wall_\d+_grp$/i.test(name) || /^Wall\d+$/i.test(name)) {
      hasWallNode = true;
    }
    cursor = cursor.parent;
  }

  return hasWallNode;
}

// isUsdWallMesh와 같은 방식으로 바닥 mesh를 판별한다("Floor"/"Ground"/"Slab" 이름 패턴).
export function isUsdFloorMesh(object) {
  if (!object.isMesh) return false;
  if (object.userData.isUsdFloorMesh) return true;

  let cursor = object;
  while (cursor) {
    const name = cursor.name || "";
    if (/^(Door|Window)\d*/i.test(name)) return false;
    if (/Floor|Ground|Slab/i.test(name)) return true;
    cursor = cursor.parent;
  }

  return false;
}

// 로컬 좌표계 Box3(축 정렬 박스)를 matrixWorld로 변환해서 월드 좌표계 OBB(회전 포함)로 만든다.
export function worldObbFromLocalBox(box, matrixWorld) {
  const center = box.getCenter(new THREE.Vector3()).applyMatrix4(matrixWorld);
  const halfSize = box.getSize(new THREE.Vector3()).multiplyScalar(0.5);
  const quaternion = new THREE.Quaternion();
  const scale = new THREE.Vector3();
  const rotationMatrix = new THREE.Matrix4();

  matrixWorld.decompose(new THREE.Vector3(), quaternion, scale);
  rotationMatrix.makeRotationFromQuaternion(quaternion);
  halfSize.multiply(
    new THREE.Vector3(Math.abs(scale.x), Math.abs(scale.y), Math.abs(scale.z)),
  );

  return new OBB(
    center,
    halfSize,
    new THREE.Matrix3().setFromMatrix4(rotationMatrix),
  );
}

// 세 축 벡터로부터 회전 행렬(Matrix3)을 만든다 (OBB의 rotation으로 쓰인다).
function matrix3FromBasis(xAxis, yAxis, zAxis) {
  return new THREE.Matrix3().setFromMatrix4(
    new THREE.Matrix4().makeBasis(xAxis, yAxis, zAxis),
  );
}

// 점들 중 가장 멀리 떨어진 두 점을 찾아 그 방향을 벽의 "길이 방향" 축으로 추정한다
// (OBB-fallback 경로에서 벽의 대략적인 방향을 정할 때 쓰인다).
function dominantHorizontalEdgeAxis(points) {
  let bestLengthSq = 0;
  const axis = new THREE.Vector3();

  for (let a = 0; a < points.length; a += 1) {
    for (let b = a + 1; b < points.length; b += 1) {
      const dx = points[b].x - points[a].x;
      const dz = points[b].z - points[a].z;
      const lengthSq = dx * dx + dz * dz;

      if (lengthSq > bestLengthSq) {
        bestLengthSq = lengthSq;
        axis.set(dx, 0, dz);
      }
    }
  }

  return bestLengthSq > 1e-8 ? axis.normalize() : null;
}

// 한 벽(연결된 정점 집합)의 점들로부터 두께/높이/길이 축이 정렬된 OBB를 만든다.
// worldWallObbsFromGeometry에서 각 연결 성분(component)마다 호출된다.
function worldWallObbFromPoints(points) {
  if (!points.length) return null;

  const lengthAxis =
    dominantHorizontalEdgeAxis(points) || new THREE.Vector3(1, 0, 0);
  const thicknessAxis = new THREE.Vector3(
    -lengthAxis.z,
    0,
    lengthAxis.x,
  );
  const heightAxis = new THREE.Vector3(0, 1, 0);

  const axes = {
    x: thicknessAxis,
    y: heightAxis,
    z: lengthAxis,
  };
  const ranges = Object.fromEntries(
    Object.entries(axes).map(([axisName, axis]) => {
      let min = Infinity;
      let max = -Infinity;

      points.forEach((point) => {
        const projected = point.dot(axis);
        min = Math.min(min, projected);
        max = Math.max(max, projected);
      });

      return [axisName, { min, max }];
    }),
  );

  if (
    Object.values(ranges).some(
      ({ min, max }) => !Number.isFinite(min) || !Number.isFinite(max),
    )
  ) {
    return null;
  }

  const center = new THREE.Vector3();
  Object.entries(axes).forEach(([axisName, axis]) => {
    const range = ranges[axisName];
    center.addScaledVector(axis, (range.min + range.max) / 2);
  });

  const halfSize = new THREE.Vector3(
    Math.max((ranges.x.max - ranges.x.min) / 2, wallConfigNumber("colliderHalfThickness")),
    Math.max((ranges.y.max - ranges.y.min) / 2, wallConfigNumber("colliderHalfThickness")),
    Math.max((ranges.z.max - ranges.z.min) / 2, wallConfigNumber("colliderHalfThickness")),
  );
  const rotation = matrix3FromBasis(thicknessAxis, heightAxis, lengthAxis);

  return new OBB(center, halfSize, rotation);
}

// 정점 좌표를 반올림해 키로 만든다 (부동소수점 오차로 같은 점이 다르게 인식되는 걸 방지).
function quantizedPointKey(position, index) {
  return [
    Math.round(position.getX(index) * 100000),
    Math.round(position.getY(index) * 100000),
    Math.round(position.getZ(index) * 100000),
  ].join(":");
}

// union-find(서로소 집합) 자료구조의 find 연산 — 경로 압축 포함.
// worldWallObbsFromGeometry에서 같은 벽에 속한 정점/삼각형들을 하나의 그룹으로 묶는 데 쓰인다.
function findRoot(parents, index) {
  let root = index;
  while (parents[root] !== root) {
    root = parents[root];
  }

  while (parents[index] !== index) {
    const parent = parents[index];
    parents[index] = root;
    index = parent;
  }

  return root;
}

// union-find의 union 연산 — 두 정점을 같은 그룹으로 합친다.
function unionRoots(parents, a, b) {
  const rootA = findRoot(parents, a);
  const rootB = findRoot(parents, b);
  if (rootA !== rootB) parents[rootB] = rootA;
}

// 벽 mesh의 정점들을 연결된 성분(같은 벽)별로 묶어서 각각 OBB 하나씩 만든다.
// 현재 실제 콜라이더 생성(createWallColliders)은 삼각형 단위인 worldWallFaceCollidersFromGeometry를
// 쓰고 있어서, 이 함수는 다른 곳에서 호출되지 않는다(예전 방식이거나 향후 대안 구현).
export function worldWallObbsFromGeometry(object) {
  const geometry = object.geometry;
  const position = geometry?.attributes?.position;
  if (!position) return [];

  const parents = Array.from({ length: position.count }, (_, index) => index);
  const verticesByPosition = new Map();

  for (let index = 0; index < position.count; index += 1) {
    const key = quantizedPointKey(position, index);
    const existingIndex = verticesByPosition.get(key);

    if (existingIndex == null) {
      verticesByPosition.set(key, index);
    } else {
      unionRoots(parents, existingIndex, index);
    }
  }

  const indices = geometry.index?.array;
  const triangleCount = indices ? indices.length / 3 : position.count / 3;
  for (let triangle = 0; triangle < triangleCount; triangle += 1) {
    const a = indices ? indices[triangle * 3] : triangle * 3;
    const b = indices ? indices[triangle * 3 + 1] : triangle * 3 + 1;
    const c = indices ? indices[triangle * 3 + 2] : triangle * 3 + 2;

    unionRoots(parents, a, b);
    unionRoots(parents, b, c);
  }

  object.updateWorldMatrix(true, false);
  const vertex = new THREE.Vector3();
  const components = new Map();
  for (let index = 0; index < position.count; index += 1) {
    const root = findRoot(parents, index);

    if (!components.has(root)) {
      components.set(root, []);
    }

    vertex.fromBufferAttribute(position, index).applyMatrix4(object.matrixWorld);
    components.get(root).push(vertex.clone());
  }

  return Array.from(components.values())
    .filter((points) => {
      const bounds = new THREE.Box3().setFromPoints(points);
      const size = bounds.getSize(new THREE.Vector3());

      return points.length >= 3 && size.y > 0.05 && Math.max(size.x, size.z) > 0.05;
    })
    .map(worldWallObbFromPoints)
    .filter(Boolean);
}

// 수평 법선을 정규화된 "대표 방향"으로 통일한다 (같은 벽의 앞/뒤 면이 서로 반대 방향
// 법선을 갖더라도, canonicalize하면 같은 방향으로 취급되어 face 그룹핑이 일관되게 된다).
function canonicalHorizontalNormal(normal) {
  const horizontalNormal = new THREE.Vector3(normal.x, 0, normal.z);
  if (horizontalNormal.lengthSq() < 1e-8) return null;

  horizontalNormal.normalize();
  if (
    horizontalNormal.x < 0 ||
    (Math.abs(horizontalNormal.x) < 1e-6 && horizontalNormal.z < 0)
  ) {
    horizontalNormal.multiplyScalar(-1);
  }

  return horizontalNormal;
}

// 점을 여러 축에 투영해서 각 축의 min/max 범위를 갱신한다.
function addPointRange(ranges, point, axes) {
  Object.entries(axes).forEach(([axisName, axis]) => {
    const projected = point.dot(axis);
    ranges[axisName].min = Math.min(ranges[axisName].min, projected);
    ranges[axisName].max = Math.max(ranges[axisName].max, projected);
  });
}

// 2D 외적 부호(collision.js의 cross2D와 동일 역할, "length/height" 좌표계 버전).
function crossSpan2D(a, b, c) {
  return (
    (b.length - a.length) * (c.height - a.height) -
    (b.height - a.height) * (c.length - a.length)
  );
}

// 벽 face 점들의 볼록 껍질(spanPolygon)을 구한다 — 벽의 정확한 외곽선 모양을 나타내며,
// 가구가 이 다각형과 겹치는지 정밀 판정(objectOverlapsWallSpan)하는 데 쓰인다.
function spanConvexHull(points) {
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
      crossSpan2D(lower[lower.length - 2], lower[lower.length - 1], point) <=
        1e-10
    ) {
      lower.pop();
    }
    lower.push(point);
  });

  const upper = [];
  [...uniquePoints].reverse().forEach((point) => {
    while (
      upper.length >= 2 &&
      crossSpan2D(upper[upper.length - 2], upper[upper.length - 1], point) <=
        1e-10
    ) {
      upper.pop();
    }
    upper.push(point);
  });

  lower.pop();
  upper.pop();

  return [...lower, ...upper];
}

// XZ 평면에서 점이 삼각형 안에 있는지 판정한다 (barycentric 부호 검사).
function pointInTriangleXZ(point, a, b, c) {
  const area =
    (b.x - a.x) * (c.z - a.z) -
    (b.z - a.z) * (c.x - a.x);
  if (Math.abs(area) < 1e-10) return false;

  const sideA =
    (b.x - a.x) * (point.z - a.z) -
    (b.z - a.z) * (point.x - a.x);
  const sideB =
    (c.x - b.x) * (point.z - b.z) -
    (c.z - b.z) * (point.x - b.x);
  const sideC =
    (a.x - c.x) * (point.z - c.z) -
    (a.z - c.z) * (point.x - c.x);
  const hasNegative = sideA < -1e-8 || sideB < -1e-8 || sideC < -1e-8;
  const hasPositive = sideA > 1e-8 || sideB > 1e-8 || sideC > 1e-8;

  return !(hasNegative && hasPositive);
}

// 점(XZ 좌표)이 바닥 삼각형들 중 어느 하나 위에 있는지 — "이 위치가 방 안쪽인가?"를
// 판정하는 데 쓰인다(roomSideFromFloorSamples).
function pointIsOverFloor(point, floorTriangles) {
  return floorTriangles.some((triangle) =>
    pointInTriangleXZ(point, triangle.a, triangle.b, triangle.c),
  );
}

// 방의 바닥 mesh에서 모든 삼각형을 XZ 평면 좌표로 수집한다.
function collectFloorTriangles(roomModel) {
  const floorTriangles = [];
  const vertexA = new THREE.Vector3();
  const vertexB = new THREE.Vector3();
  const vertexC = new THREE.Vector3();
  const edgeA = new THREE.Vector3();
  const edgeB = new THREE.Vector3();
  const normal = new THREE.Vector3();

  roomModel.traverse((object) => {
    if (!isUsdFloorMesh(object) || !object.geometry) return;

    const position = object.geometry.attributes?.position;
    if (!position) return;

    object.updateWorldMatrix(true, false);
    const indices = object.geometry.index?.array;
    const triangleCount = indices ? indices.length / 3 : position.count / 3;

    for (let triangle = 0; triangle < triangleCount; triangle += 1) {
      const ai = indices ? indices[triangle * 3] : triangle * 3;
      const bi = indices ? indices[triangle * 3 + 1] : triangle * 3 + 1;
      const ci = indices ? indices[triangle * 3 + 2] : triangle * 3 + 2;

      vertexA.fromBufferAttribute(position, ai).applyMatrix4(object.matrixWorld);
      vertexB.fromBufferAttribute(position, bi).applyMatrix4(object.matrixWorld);
      vertexC.fromBufferAttribute(position, ci).applyMatrix4(object.matrixWorld);

      edgeA.subVectors(vertexB, vertexA);
      edgeB.subVectors(vertexC, vertexA);
      normal.crossVectors(edgeA, edgeB);
      if (normal.lengthSq() < WALL_FACE_MIN_AREA) continue;

      normal.normalize();
      if (Math.abs(normal.y) < 0.5) continue;

      floorTriangles.push({
        a: { x: vertexA.x, z: vertexA.z },
        b: { x: vertexB.x, z: vertexB.z },
        c: { x: vertexC.x, z: vertexC.z },
      });
    }
  });

  return floorTriangles;
}

// 벽 face의 법선 방향(+)과 반대 방향(-)으로 살짝 떨어진 두 샘플점 중 어느 쪽이 바닥
// 위(방 안쪽)에 있는지로, 이 벽이 "어느 쪽을 향해야 방 안쪽인지"(roomSide)를 결정한다.
// 양쪽 다 바닥 위거나 둘 다 아니면(0 또는 null) 애매한 경우로 처리한다.
function roomSideFromFloorSamples(points, normal, floorTriangles) {
  if (!floorTriangles.length) return null;

  const center = points
    .reduce((sum, point) => sum.add(point), new THREE.Vector3())
    .multiplyScalar(1 / points.length);
  const offset = Math.max(
    FLOOR_SIDE_SAMPLE_DISTANCE,
    wallConfigNumber("colliderHalfThickness") * 6,
  );
  const plusPoint = {
    x: center.x + normal.x * offset,
    z: center.z + normal.z * offset,
  };
  const minusPoint = {
    x: center.x - normal.x * offset,
    z: center.z - normal.z * offset,
  };
  const plusInside = pointIsOverFloor(plusPoint, floorTriangles);
  const minusInside = pointIsOverFloor(minusPoint, floorTriangles);

  if (plusInside && !minusInside) return 1;
  if (!plusInside && minusInside) return -1;
  if (plusInside && minusInside) return 0;

  return null;
}

// 벽의 한 face 그룹(같은 방향 법선을 가진 삼각형들)으로부터 실제 벽 콜라이더 객체를 만든다.
// roomSide가 판정되면 roomFacingNormal/roomFacingProjection(경계선 기반 판정용)까지 채우고,
// 애매하면(null) 그 정보 없이(solid OBB 판정으로 fallback되는) 콜라이더를 만든다.
function createWallColliderFromFaceGroup(
  object,
  group,
  roomCenter,
  floorTriangles = [],
) {
  const normal = group.normal.clone().normalize();
  const projection =
    group.projectionSum / Math.max(group.projectionCount, 1);
  const sampledRoomSide = roomSideFromFloorSamples(
    group.points,
    normal,
    floorTriangles,
  );
  const roomSide = sampledRoomSide;
  const boundaryRoomSide = roomSide === 0 ? null : roomSide;
  const roomFacingNormal =
    boundaryRoomSide == null
      ? null
      : normal.clone().multiplyScalar(boundaryRoomSide);
  const roomFacingProjection =
    boundaryRoomSide == null ? null : projection * boundaryRoomSide;
  const thicknessAxis = roomFacingNormal || normal.clone();
  const planeProjection =
    boundaryRoomSide == null ? projection : roomFacingProjection;
  const lengthAxis = new THREE.Vector3(
    -thicknessAxis.z,
    0,
    thicknessAxis.x,
  ).normalize();
  const heightAxis = new THREE.Vector3(0, 1, 0);
  const ranges = {
    length: { min: Infinity, max: -Infinity },
    height: { min: Infinity, max: -Infinity },
  };

  group.points.forEach((point) =>
    addPointRange(ranges, point, {
      length: lengthAxis,
      height: heightAxis,
    }),
  );

  if (
    Object.values(ranges).some(
      ({ min, max }) => !Number.isFinite(min) || !Number.isFinite(max),
    )
  ) {
    return null;
  }

  const length = ranges.length.max - ranges.length.min;
  const height = ranges.height.max - ranges.height.min;
  if (length < WALL_FACE_MIN_LENGTH || height < WALL_FACE_MIN_HEIGHT) {
    return null;
  }

  const center = thicknessAxis
    .clone()
    .multiplyScalar(planeProjection)
    .addScaledVector(lengthAxis, (ranges.length.min + ranges.length.max) / 2)
    .addScaledVector(heightAxis, (ranges.height.min + ranges.height.max) / 2);
  const halfSize = new THREE.Vector3(
    wallConfigNumber("colliderHalfThickness"),
    height / 2,
    length / 2,
  );
  const obb = new OBB(
    center,
    halfSize,
    matrix3FromBasis(thicknessAxis, heightAxis, lengthAxis),
  );
  const spanPolygon = spanConvexHull(
    group.points.map((point) => ({
      height: point.dot(heightAxis),
      length: point.dot(lengthAxis),
    })),
  );

  return {
    object,
    obb,
    spanAxes: [
      { name: "height", axis: heightAxis, halfSize: halfSize.y },
      { name: "length", axis: lengthAxis, halfSize: halfSize.z },
    ],
    spanPolygon,
    roomFacingNormal,
    roomFacingProjection,
    triangleStart: group.triangleStart,
    triangleCount: group.triangleCount,
  };
}

// 벽 mesh의 삼각형을 하나씩 순회하며, 수평에 가까운 법선(WALL_FACE_NORMAL_Y_LIMIT 이내)을
// 가진 삼각형마다 개별 콜라이더를 만든다. createWallColliders()가 실제로 쓰는 메인 경로다.
export function worldWallFaceCollidersFromGeometry(
  object,
  roomCenter,
  floorTriangles = [],
) {
  const geometry = object.geometry;
  const position = geometry?.attributes?.position;
  if (!position) return [];

  object.updateWorldMatrix(true, false);

  const indices = geometry.index?.array;
  const triangleCount = indices ? indices.length / 3 : position.count / 3;
  const a = new THREE.Vector3();
  const b = new THREE.Vector3();
  const c = new THREE.Vector3();
  const edgeA = new THREE.Vector3();
  const edgeB = new THREE.Vector3();
  const normal = new THREE.Vector3();
  const colliders = [];

  for (let triangle = 0; triangle < triangleCount; triangle += 1) {
    const ai = indices ? indices[triangle * 3] : triangle * 3;
    const bi = indices ? indices[triangle * 3 + 1] : triangle * 3 + 1;
    const ci = indices ? indices[triangle * 3 + 2] : triangle * 3 + 2;

    a.fromBufferAttribute(position, ai).applyMatrix4(object.matrixWorld);
    b.fromBufferAttribute(position, bi).applyMatrix4(object.matrixWorld);
    c.fromBufferAttribute(position, ci).applyMatrix4(object.matrixWorld);

    edgeA.subVectors(b, a);
    edgeB.subVectors(c, a);
    normal.crossVectors(edgeA, edgeB);
    const area = normal.length() / 2;
    if (area < WALL_FACE_MIN_AREA) continue;

    normal.normalize();
    if (Math.abs(normal.y) > WALL_FACE_NORMAL_Y_LIMIT) continue;

    const horizontalNormal = canonicalHorizontalNormal(normal);
    if (!horizontalNormal) continue;

    const collider = createWallColliderFromFaceGroup(
      object,
      {
        normal: horizontalNormal.clone(),
        points: [a.clone(), b.clone(), c.clone()],
        projectionCount: 3,
        projectionSum:
          a.dot(horizontalNormal) +
          b.dot(horizontalNormal) +
          c.dot(horizontalNormal),
        triangleStart: triangle * 3,
        triangleCount: 3,
      },
      roomCenter,
      floorTriangles,
    );

    if (collider) colliders.push(collider);
  }

  return colliders;
}

// position에서 가장 가까운 벽 mesh를 찾는다. 문/창문은 벽에 뚫린 개구부(hole) 위에
// 있어서 벽 mesh의 삼각형(triangle) 자체와는 겹치지 않으므로, 벽의 world bounding box까지의
// 거리(안에 있으면 0)로 판정한다. per-triangle face collider를 쓰지 않는 이유는, 문/창문
// 개구부 주변에는 문틀 옆면(reveal)처럼 진짜 두께 방향과 무관한(벽 길이 방향을 향하는)
// 삼각형도 섞여 있어서, 그런 삼각형을 기준으로 삼으면 두께 축을 잘못 잡기 때문이다.
function nearestWallMesh(position, wallMeshes, maxDistance) {
  let best = null;
  let bestDistance = Infinity;
  const box = new THREE.Box3();

  (wallMeshes || []).forEach((object) => {
    if (!object?.geometry) return;

    object.updateWorldMatrix(true, false);
    box.setFromObject(object);
    const distance = box.distanceToPoint(position);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = object;
    }
  });

  return best && bestDistance <= maxDistance
    ? { object: best, distance: bestDistance }
    : null;
}

// mesh 하나의 로컬 bounding box에서 가장 짧은 축을 두께 방향으로 본다. 벽 mesh는
// 길이/높이에 비해 두께가 훨씬 얇은 박스 형태로 스캔되므로 이 축이 실제 두께 방향과 일치한다.
function localThicknessAxis(object) {
  const position = object.geometry?.attributes?.position;
  if (!position) return null;

  const localBounds = new THREE.Box3();
  const vertex = new THREE.Vector3();
  for (let index = 0; index < position.count; index += 1) {
    vertex.fromBufferAttribute(position, index);
    localBounds.expandByPoint(vertex);
  }

  const size = localBounds.getSize(new THREE.Vector3());
  const sizes = [size.x, size.y, size.z];
  let thinnestIndex = 0;
  if (sizes[1] < sizes[thinnestIndex]) thinnestIndex = 1;
  if (sizes[2] < sizes[thinnestIndex]) thinnestIndex = 2;

  const localAxis = new THREE.Vector3(
    thinnestIndex === 0 ? 1 : 0,
    thinnestIndex === 1 ? 1 : 0,
    thinnestIndex === 2 ? 1 : 0,
  );
  const quaternion = new THREE.Quaternion();
  object.matrixWorld.decompose(
    new THREE.Vector3(),
    quaternion,
    new THREE.Vector3(),
  );

  return localAxis.applyQuaternion(quaternion).normalize();
}

// 문/창문이 속한 벽의 실제 두께와 두께 방향 중심 위치를 잰다. wallMeshes는 벽 mesh
// object 배열이다(wallColliders의 collider가 아니라 원본 mesh). 가까이에 벽을 찾지
// 못하면(거리 maxDistance 초과) null을 반환한다.
export function measureWallThicknessAtPosition(
  position,
  wallMeshes,
  maxDistance = 0.5,
) {
  const nearest = nearestWallMesh(position, wallMeshes, maxDistance);
  if (!nearest) return null;

  const normal = localThicknessAxis(nearest.object);
  if (!normal) return null;

  const range = geometryProjectionRange(nearest.object, normal);
  if (!range) return null;

  const thickness = range.max - range.min;
  if (!Number.isFinite(thickness) || thickness <= 0.01) return null;

  return {
    thickness,
    normal,
    centerProjection: (range.min + range.max) / 2,
    object: nearest.object,
  };
}

// mesh의 모든 정점(월드 좌표)을 direction 축에 투영했을 때의 min/max 범위.
// 벽 실측 두께 계산(measureWallThicknessAtPosition)과 벽 중심 투영 계산에 쓰인다.
export function geometryProjectionRange(object, direction) {
  const position = object.geometry?.attributes?.position;
  if (!position) return null;

  const vertex = new THREE.Vector3();
  let min = Infinity;
  let max = -Infinity;

  for (let i = 0; i < position.count; i += 1) {
    vertex.fromBufferAttribute(position, i).applyMatrix4(object.matrixWorld);
    const projected = vertex.dot(direction);
    min = Math.min(min, projected);
    max = Math.max(max, projected);
  }

  return Number.isFinite(min) && Number.isFinite(max) ? { min, max } : null;
}

// 방 모델의 모든 벽 mesh로부터 충돌 판정용 콜라이더 배열을 만든다. 벽마다 우선
// worldWallFaceCollidersFromGeometry(삼각형 단위, roomFacingNormal 포함)를 시도하고,
// face 정보를 못 만들면 mesh 전체 bounding box 기반 OBB(fallback)로 만든다.
// fallback OBB는 두께를 colliderHalfThickness로 강제로 얇게 깎아서 "충돌용 얇은 평면"으로 만든다.
export function createWallColliders(roomModel) {
  const colliders = [];
  roomModel.updateWorldMatrix(true, true);
  const roomCenter = new THREE.Box3()
    .setFromObject(roomModel)
    .getCenter(new THREE.Vector3());
  const floorTriangles = collectFloorTriangles(roomModel);

  roomModel.traverse((object) => {
    if (!isUsdWallMesh(object) || !object.geometry) return;

    const faceColliders = worldWallFaceCollidersFromGeometry(
      object,
      roomCenter,
      floorTriangles,
    );

    if (faceColliders.length) {
      colliders.push(...faceColliders);
      return;
    }

    object.geometry.computeBoundingBox();
    if (!object.geometry.boundingBox || object.geometry.boundingBox.isEmpty())
      return;

    const wallObb = worldObbFromLocalBox(
      object.geometry.boundingBox,
      object.matrixWorld,
    );
    const thinnestAxis =
      wallObb.halfSize.x <= wallObb.halfSize.y &&
      wallObb.halfSize.x <= wallObb.halfSize.z
        ? "x"
        : wallObb.halfSize.y <= wallObb.halfSize.z
          ? "y"
          : "z";
    const originalHalfThickness = wallObb.halfSize[thinnestAxis];
    const nextHalfThickness = Math.min(
      originalHalfThickness,
      wallConfigNumber("colliderHalfThickness"),
    );
    const wallAxes = {
      x: new THREE.Vector3(),
      y: new THREE.Vector3(),
      z: new THREE.Vector3(),
    };
    wallObb.rotation.extractBasis(wallAxes.x, wallAxes.y, wallAxes.z);
    const wallNormal = wallAxes[thinnestAxis].clone().normalize();
    const spanAxes = Object.entries(wallAxes)
      .filter(([axisName]) => axisName !== thinnestAxis)
      .map(([axisName, axis]) => ({
        axis: axis.clone().normalize(),
        halfSize: wallObb.halfSize[axisName],
      }));
    const renderRange = geometryProjectionRange(object, wallNormal);
    const wallCenterProjection = renderRange
      ? (renderRange.min + renderRange.max) / 2
      : wallObb.center.dot(wallNormal);
    const roomSide =
      roomCenter.dot(wallNormal) >= wallCenterProjection ? 1 : -1;
    const roomFacingProjection = renderRange
      ? roomSide > 0
        ? renderRange.max
        : renderRange.min
      : wallObb.center.dot(wallNormal) + roomSide * originalHalfThickness;
    const nextCenterProjection =
      roomFacingProjection - roomSide * nextHalfThickness;
    const centerCorrection =
      nextCenterProjection - wallObb.center.dot(wallNormal);

    wallObb.center.addScaledVector(wallNormal, centerCorrection);
    wallObb.halfSize[thinnestAxis] = nextHalfThickness;

    colliders.push({
      object,
      obb: wallObb,
      spanAxes,
      roomFacingNormal: wallNormal.clone().multiplyScalar(roomSide),
      roomFacingProjection: roomFacingProjection * roomSide,
    });
  });

  return colliders;
}

// 벽 디버그 시각화용 — 벽의 "경계선" 중심 위치(roomFacingProjection 기준)를 계산한다.
function wallBoundaryCenter(wall, normal) {
  if (!normal || !Number.isFinite(wall.roomFacingProjection)) {
    return wall.obb.center.clone();
  }

  const boundaryProjection =
    wall.roomFacingProjection - wallConfigNumber("boundaryEpsilon");

  return wall.obb.center
    .clone()
    .addScaledVector(normal, boundaryProjection - wall.obb.center.dot(normal));
}

// 벽 디버그 시각화용 — 경계선 사각형을 그리기 위한 두 축(길이/높이)을 구한다.
function wallBoundarySpanAxes(wall, normal) {
  const spans = (wall.spanAxes || [])
    .filter(({ axis, halfSize }) => axis && Number.isFinite(halfSize))
    .map(({ axis, halfSize }) => ({
      axis: axis.clone().normalize(),
      halfSize,
    }));

  if (spans.length >= 2) return spans.slice(0, 2);

  const axes = {
    x: new THREE.Vector3(),
    y: new THREE.Vector3(),
    z: new THREE.Vector3(),
  };

  wall.obb.rotation.extractBasis(axes.x, axes.y, axes.z);

  return Object.entries(axes)
    .filter(([, axis]) => !normal || Math.abs(axis.dot(normal)) < 0.75)
    .map(([axisName, axis]) => ({
      axis: axis.clone().normalize(),
      halfSize: wall.obb.halfSize[axisName],
    }))
    .slice(0, 2);
}

// 벽 경계선을 사각형 윤곽선(LineSegments 지오메트리)으로 만든다 (디버그 시각화용).
function createBoundaryOutlineGeometry(center, spanAxes) {
  if (spanAxes.length < 2) return null;

  const firstSpan = spanAxes[0].axis
    .clone()
    .multiplyScalar(spanAxes[0].halfSize);
  const secondSpan = spanAxes[1].axis
    .clone()
    .multiplyScalar(spanAxes[1].halfSize);
  const corners = [
    center.clone().sub(firstSpan).sub(secondSpan),
    center.clone().add(firstSpan).sub(secondSpan),
    center.clone().add(firstSpan).add(secondSpan),
    center.clone().sub(firstSpan).add(secondSpan),
  ];

  return new THREE.BufferGeometry().setFromPoints([
    corners[0],
    corners[1],
    corners[1],
    corners[2],
    corners[2],
    corners[3],
    corners[3],
    corners[0],
  ]);
}

// 벽 바닥선(경계 사각형의 아랫변)만 강조해서 그리는 지오메트리 (디버그 시각화용).
function createBoundaryBaselineGeometry(center, spanAxes) {
  if (spanAxes.length < 2) return null;

  const sortedSpans = [...spanAxes].sort(
    (a, b) => Math.abs(b.axis.y) - Math.abs(a.axis.y),
  );
  const verticalSpan = sortedSpans[0];
  const horizontalSpan = sortedSpans[1];
  if (Math.abs(verticalSpan.axis.y) < 0.5) return null;

  const upAxis = verticalSpan.axis
    .clone()
    .multiplyScalar(verticalSpan.axis.y >= 0 ? 1 : -1);
  const lineAxis = horizontalSpan.axis
    .clone()
    .multiplyScalar(horizontalSpan.halfSize);
  const bottomCenter = center
    .clone()
    .addScaledVector(upAxis, -verticalSpan.halfSize);

  return new THREE.BufferGeometry().setFromPoints([
    bottomCenter.clone().sub(lineAxis),
    bottomCenter.clone().add(lineAxis),
  ]);
}

// 벽 콜라이더들을 눈에 보이는 선(OBB 박스 외곽선 + 경계 사각형 + 바닥선)으로 그려주는
// 디버그 레이어를 만든다. showColliderDebug/충돌·차단 벽 하이라이트 등에 쓰인다.
export function createWallColliderVisuals(wallColliders, options = {}) {
  const group = new THREE.Group();
  const color = options.color || sceneColor("wallColliderDebug");
  const opacityMultiplier = options.opacityMultiplier ?? 1;
  const renderOrderOffset = options.renderOrderOffset || 0;

  group.name = options.name || "WallColliderDebugLayer";

  wallColliders.forEach((wall, index) => {
    const normal = wall.roomFacingNormal?.clone().normalize();
    const spanAxes = wallBoundarySpanAxes(wall, normal);
    const center = wallBoundaryCenter(wall, normal);
    const outlineGeometry = createBoundaryOutlineGeometry(center, spanAxes);
    const baselineGeometry = createBoundaryBaselineGeometry(center, spanAxes);
    const colliderSize = wall.obb.halfSize.clone().multiplyScalar(2);
    const colliderGeometry = new THREE.BoxGeometry(
      colliderSize.x,
      colliderSize.y,
      colliderSize.z,
    );
    const colliderEdge = new THREE.LineSegments(
      new THREE.EdgesGeometry(colliderGeometry),
      new THREE.LineBasicMaterial({
        color,
        transparent: true,
        opacity: 0.42 * opacityMultiplier,
        depthTest: false,
        depthWrite: false,
      }),
    );
    const colliderRotation = new THREE.Matrix4().setFromMatrix3(
      wall.obb.rotation,
    );

    const outline = outlineGeometry
      ? new THREE.LineSegments(
          outlineGeometry,
          new THREE.LineBasicMaterial({
            color,
            transparent: true,
            opacity: 0.58 * opacityMultiplier,
            depthTest: false,
            depthWrite: false,
          }),
        )
      : null;
    const baseline = baselineGeometry
      ? new THREE.Line(
          baselineGeometry,
          new THREE.LineBasicMaterial({
            color,
            transparent: true,
            opacity: 0.98 * opacityMultiplier,
            depthTest: false,
            depthWrite: false,
          }),
        )
      : null;
    colliderEdge.name = `wall-collider-obb-edge-${index + 1}`;
    colliderEdge.position.copy(wall.obb.center);
    colliderEdge.quaternion.setFromRotationMatrix(colliderRotation);
    colliderEdge.renderOrder = 20 + renderOrderOffset;
    group.add(colliderEdge);

    if (outline) {
      outline.name = `wall-collider-boundary-outline-${index + 1}`;
      outline.renderOrder = 21 + renderOrderOffset;
      group.add(outline);
    }

    if (baseline) {
      baseline.name = `wall-collider-boundary-line-${index + 1}`;
      baseline.renderOrder = 22 + renderOrderOffset;
      group.add(baseline);
    }
  });

  return group;
}

// 방 모델 로딩 직후 한 번 호출된다. 그림자를 받도록 설정하고, 앱이 대체한 원본 스캔
// mesh(isUsdReplacedMesh)는 화면에서 숨긴다.
export function prepareRoomModel(model) {
  model.traverse((object) => {
    if (!object.isMesh) return;
    object.receiveShadow = true;

    if (isUsdReplacedMesh(object)) {
      object.visible = false;
    }
  });
}
