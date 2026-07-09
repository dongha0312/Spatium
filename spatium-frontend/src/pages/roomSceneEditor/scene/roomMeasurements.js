import * as THREE from "three";
import { isUsdFloorMesh } from "./wallColliders";

const FLOOR_PLANE_PRECISION = 1000;
const MIN_TRIANGLE_AREA = 1e-6;
const POINT_PRECISION = 1000;

// 좌표를 반올림해서 문자열 키로 만든다 — 부동소수점 오차 때문에 같은 점인데 다르게
// 판정되는 걸 막기 위함(정점 병합/외곽선 edge 매칭에 사용).
function pointKey(point) {
  return [
    Math.round(point.x * POINT_PRECISION),
    Math.round(point.z * POINT_PRECISION),
  ].join(":");
}

// 두 점(a,b)으로 이뤄진 선분의 방향과 무관한 키를 만든다 — 같은 edge를 양쪽 삼각형에서
// 각각 만나도 하나로 인식되게 하기 위함(외곽선 판정: count===1이면 바깥쪽 edge).
function segmentKey(a, b) {
  const aKey = pointKey(a);
  const bKey = pointKey(b);
  return aKey < bKey ? `${aKey}|${bKey}` : `${bKey}|${aKey}`;
}

// 바닥 평면(XZ)에 투영했을 때 삼각형의 면적.
function triangleAreaOnFloor(a, b, c) {
  return Math.abs(
    (a.x * (b.z - c.z) + b.x * (c.z - a.z) + c.x * (a.z - b.z)) / 2,
  );
}

function addPointToBounds(bounds, point) {
  bounds.minX = Math.min(bounds.minX, point.x);
  bounds.maxX = Math.max(bounds.maxX, point.x);
  bounds.minZ = Math.min(bounds.minZ, point.z);
  bounds.maxZ = Math.max(bounds.maxZ, point.z);
}

function emptyBounds() {
  return {
    minX: Infinity,
    maxX: -Infinity,
    minZ: Infinity,
    maxZ: -Infinity,
  };
}

function boundsAreValid(bounds) {
  return (
    Number.isFinite(bounds.minX) &&
    Number.isFinite(bounds.maxX) &&
    Number.isFinite(bounds.minZ) &&
    Number.isFinite(bounds.maxZ)
  );
}

// 삼각형이 속한 "바닥 높이(Y)"를 키로 만든다. 방에 단차가 있으면(예: 현관/거실 높이 차이)
// 같은 Y에 있는 삼각형끼리만 하나의 바닥 그룹으로 묶기 위함.
function floorPlaneKey(a, b, c) {
  const averageY = (a.y + b.y + c.y) / 3;
  return String(Math.round(averageY * FLOOR_PLANE_PRECISION));
}

// 바닥 mesh의 모든 삼각형을 Y높이별로 그룹핑하면서, 그룹별 면적/바운드/edge(변) 사용
// 횟수를 누적한다. edge 사용 횟수가 1이면 그 edge는 바닥의 바깥 테두리(구멍이 아닌 한)다.
function collectFloorAreaGroups(roomModel) {
  const groups = new Map();
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

      if (normal.lengthSq() < MIN_TRIANGLE_AREA) continue;

      normal.normalize();
      if (Math.abs(normal.y) < 0.5) continue;

      const area = triangleAreaOnFloor(vertexA, vertexB, vertexC);
      if (area < MIN_TRIANGLE_AREA) continue;

      const key = floorPlaneKey(vertexA, vertexB, vertexC);
      const group = groups.get(key) || {
        area: 0,
        bounds: emptyBounds(),
        edges: new Map(),
      };

      group.area += area;
      addPointToBounds(group.bounds, vertexA);
      addPointToBounds(group.bounds, vertexB);
      addPointToBounds(group.bounds, vertexC);
      [
        [vertexA, vertexB],
        [vertexB, vertexC],
        [vertexC, vertexA],
      ].forEach(([start, end]) => {
        const edgeKey = segmentKey(start, end);
        const existing = group.edges.get(edgeKey);

        if (existing) {
          existing.count += 1;
        } else {
          group.edges.set(edgeKey, {
            count: 1,
            start: start.clone(),
            end: end.clone(),
          });
        }
      });
      groups.set(key, group);
    }
  });

  return Array.from(groups.values());
}

// 여러 바닥 높이 그룹 중 면적이 가장 넓은 것을 "메인 바닥"으로 선택한다
// (단차/작은 조각들은 무시하고 주된 방 면적만 쓰기 위함).
function largestFloorGroup(roomModel) {
  return collectFloorAreaGroups(roomModel).reduce(
    (largest, group) => (!largest || group.area > largest.area ? group : largest),
    null,
  );
}

// 방의 폭/깊이/높이/면적과, 치수 표시용 외곽선/높이선을 계산한다.
// 바닥 mesh를 찾으면 실제 바닥 폴리곤 기준(area: "floor")으로, 못 찾으면 방 전체
// bounding box 기준(area: "bounds")으로 fallback한다.
export function calculateRoomMeasurements(roomModel) {
  if (!roomModel) return null;

  roomModel.updateWorldMatrix(true, true);

  const roomBounds = new THREE.Box3().setFromObject(roomModel);
  if (roomBounds.isEmpty()) return null;

  const size = roomBounds.getSize(new THREE.Vector3());
  const floorGroup = largestFloorGroup(roomModel);
  const floorBounds = floorGroup?.bounds;
  const hasFloorBounds = floorBounds && boundsAreValid(floorBounds);

  const width = hasFloorBounds ? floorBounds.maxX - floorBounds.minX : size.x;
  const depth = hasFloorBounds ? floorBounds.maxZ - floorBounds.minZ : size.z;
  const height = size.y;
  const area = floorGroup?.area || width * depth;
  const measurementY = hasFloorBounds
    ? Array.from(floorGroup.edges.values())[0]?.start.y ?? roomBounds.min.y
    : roomBounds.min.y;
  const outlineBounds = hasFloorBounds
    ? floorBounds
    : {
        minX: roomBounds.min.x,
        maxX: roomBounds.max.x,
        minZ: roomBounds.min.z,
        maxZ: roomBounds.max.z,
      };
  const heightLineX = outlineBounds.maxX + 0.18;
  const heightLineZ = outlineBounds.minZ - 0.18;
  const outlineSegments = floorGroup
    ? Array.from(floorGroup.edges.values())
        .filter((edge) => edge.count === 1)
        .map((edge) => {
          const dx = edge.end.x - edge.start.x;
          const dz = edge.end.z - edge.start.z;
          return {
            start: { x: edge.start.x, y: edge.start.y, z: edge.start.z },
            end: { x: edge.end.x, y: edge.end.y, z: edge.end.z },
            length: Math.hypot(dx, dz),
          };
        })
        .filter((segment) => segment.length > 0.08)
    : [
        {
          start: { x: outlineBounds.minX, y: measurementY, z: outlineBounds.minZ },
          end: { x: outlineBounds.maxX, y: measurementY, z: outlineBounds.minZ },
          length: width,
        },
        {
          start: { x: outlineBounds.maxX, y: measurementY, z: outlineBounds.minZ },
          end: { x: outlineBounds.maxX, y: measurementY, z: outlineBounds.maxZ },
          length: depth,
        },
        {
          start: { x: outlineBounds.maxX, y: measurementY, z: outlineBounds.maxZ },
          end: { x: outlineBounds.minX, y: measurementY, z: outlineBounds.maxZ },
          length: width,
        },
        {
          start: { x: outlineBounds.minX, y: measurementY, z: outlineBounds.maxZ },
          end: { x: outlineBounds.minX, y: measurementY, z: outlineBounds.minZ },
          length: depth,
        },
      ];

  return {
    width,
    depth,
    height,
    area,
    areaSource: floorGroup ? "floor" : "bounds",
    center: {
      x: (outlineBounds.minX + outlineBounds.maxX) / 2,
      y: measurementY,
      z: (outlineBounds.minZ + outlineBounds.maxZ) / 2,
    },
    heightSegment: {
      start: { x: heightLineX, y: roomBounds.min.y, z: heightLineZ },
      end: { x: heightLineX, y: roomBounds.max.y, z: heightLineZ },
      length: height,
    },
    outlineSegments,
  };
}
