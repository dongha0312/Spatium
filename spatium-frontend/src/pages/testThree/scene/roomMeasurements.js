import * as THREE from "three";
import { isUsdFloorMesh } from "./wallColliders";

const FLOOR_PLANE_PRECISION = 1000;
const MIN_TRIANGLE_AREA = 1e-6;
const POINT_PRECISION = 1000;

function pointKey(point) {
  return [
    Math.round(point.x * POINT_PRECISION),
    Math.round(point.z * POINT_PRECISION),
  ].join(":");
}

function segmentKey(a, b) {
  const aKey = pointKey(a);
  const bKey = pointKey(b);
  return aKey < bKey ? `${aKey}|${bKey}` : `${bKey}|${aKey}`;
}

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

function floorPlaneKey(a, b, c) {
  const averageY = (a.y + b.y + c.y) / 3;
  return String(Math.round(averageY * FLOOR_PLANE_PRECISION));
}

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

function largestFloorGroup(roomModel) {
  return collectFloorAreaGroups(roomModel).reduce(
    (largest, group) => (!largest || group.area > largest.area ? group : largest),
    null,
  );
}

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
