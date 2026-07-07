import * as THREE from "three";
import { OBB } from "three/examples/jsm/math/OBB.js";
import { sceneColor, wallConfigNumber } from "./sceneConfig";

const WALL_FACE_NORMAL_Y_LIMIT = 0.25;
const WALL_FACE_MIN_AREA = 0.000001;
const WALL_FACE_MIN_HEIGHT = 0.05;
const WALL_FACE_MIN_LENGTH = 0.05;
const FLOOR_SIDE_SAMPLE_DISTANCE = 0.12;

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

function matrix3FromBasis(xAxis, yAxis, zAxis) {
  return new THREE.Matrix3().setFromMatrix4(
    new THREE.Matrix4().makeBasis(xAxis, yAxis, zAxis),
  );
}

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

function quantizedPointKey(position, index) {
  return [
    Math.round(position.getX(index) * 100000),
    Math.round(position.getY(index) * 100000),
    Math.round(position.getZ(index) * 100000),
  ].join(":");
}

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

function unionRoots(parents, a, b) {
  const rootA = findRoot(parents, a);
  const rootB = findRoot(parents, b);
  if (rootA !== rootB) parents[rootB] = rootA;
}

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

function addPointRange(ranges, point, axes) {
  Object.entries(axes).forEach(([axisName, axis]) => {
    const projected = point.dot(axis);
    ranges[axisName].min = Math.min(ranges[axisName].min, projected);
    ranges[axisName].max = Math.max(ranges[axisName].max, projected);
  });
}

function crossSpan2D(a, b, c) {
  return (
    (b.length - a.length) * (c.height - a.height) -
    (b.height - a.height) * (c.length - a.length)
  );
}

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

function pointIsOverFloor(point, floorTriangles) {
  return floorTriangles.some((triangle) =>
    pointInTriangleXZ(point, triangle.a, triangle.b, triangle.c),
  );
}

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

export function createWallColliderVisuals(wallColliders) {
  const group = new THREE.Group();
  group.name = "WallColliderDebugLayer";

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
        color: sceneColor("wallColliderDebug"),
        transparent: true,
        opacity: 0.42,
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
            color: sceneColor("wallColliderDebug"),
            transparent: true,
            opacity: 0.58,
            depthTest: false,
            depthWrite: false,
          }),
        )
      : null;
    const baseline = baselineGeometry
      ? new THREE.Line(
          baselineGeometry,
          new THREE.LineBasicMaterial({
            color: sceneColor("wallColliderDebug"),
            transparent: true,
            opacity: 0.98,
            depthTest: false,
            depthWrite: false,
          }),
        )
      : null;
    colliderEdge.name = `wall-collider-obb-edge-${index + 1}`;
    colliderEdge.position.copy(wall.obb.center);
    colliderEdge.quaternion.setFromRotationMatrix(colliderRotation);
    colliderEdge.renderOrder = 20;
    group.add(colliderEdge);

    if (outline) {
      outline.name = `wall-collider-boundary-outline-${index + 1}`;
      outline.renderOrder = 21;
      group.add(outline);
    }

    if (baseline) {
      baseline.name = `wall-collider-boundary-line-${index + 1}`;
      baseline.renderOrder = 22;
      group.add(baseline);
    }
  });

  return group;
}

export function prepareRoomModel(model) {
  model.traverse((object) => {
    if (!object.isMesh) return;
    object.receiveShadow = true;

    if (isUsdReplacedMesh(object)) {
      object.visible = false;
    }
  });
}
