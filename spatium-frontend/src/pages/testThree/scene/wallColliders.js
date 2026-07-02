import * as THREE from "three";
import { OBB } from "three/examples/jsm/math/OBB.js";
import { sceneColor, wallConfigNumber } from "./sceneConfig";

const WALL_FACE_NORMAL_Y_LIMIT = 0.25;
const WALL_FACE_MIN_AREA = 0.000001;
const WALL_FACE_MIN_HEIGHT = 0.05;
const WALL_FACE_MIN_LENGTH = 0.05;
const WALL_FACE_ANGLE_BIN = 180 / Math.PI;
const WALL_FACE_PROJECTION_BIN = 100;

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

function wallFaceGroupKey(normal, projection) {
  const angleKey = Math.round(
    Math.atan2(normal.z, normal.x) * WALL_FACE_ANGLE_BIN,
  );
  const projectionKey = Math.round(projection * WALL_FACE_PROJECTION_BIN);

  return `${angleKey}:${projectionKey}`;
}

function addPointRange(ranges, point, axes) {
  Object.entries(axes).forEach(([axisName, axis]) => {
    const projected = point.dot(axis);
    ranges[axisName].min = Math.min(ranges[axisName].min, projected);
    ranges[axisName].max = Math.max(ranges[axisName].max, projected);
  });
}

function createWallColliderFromFaceGroup(object, group, roomCenter) {
  const normal = group.normal.clone().normalize();
  const projection =
    group.projectionSum / Math.max(group.projectionCount, 1);
  const roomSide = roomCenter.dot(normal) >= projection ? 1 : -1;
  const roomFacingNormal = normal.clone().multiplyScalar(roomSide);
  const roomFacingProjection = projection * roomSide;
  const lengthAxis = new THREE.Vector3(
    -roomFacingNormal.z,
    0,
    roomFacingNormal.x,
  ).normalize();
  const heightAxis = new THREE.Vector3(0, 1, 0);
  const thicknessAxis = roomFacingNormal.clone();
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
    .multiplyScalar(roomFacingProjection)
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

  return {
    object,
    obb,
    spanAxes: [
      { axis: heightAxis, halfSize: halfSize.y },
      { axis: lengthAxis, halfSize: halfSize.z },
    ],
    roomFacingNormal,
    roomFacingProjection,
  };
}

export function worldWallFaceCollidersFromGeometry(object, roomCenter) {
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
  const groups = new Map();

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

    const projection =
      (a.dot(horizontalNormal) +
        b.dot(horizontalNormal) +
        c.dot(horizontalNormal)) /
      3;
    const key = wallFaceGroupKey(horizontalNormal, projection);
    let group = groups.get(key);

    if (!group) {
      group = {
        normal: horizontalNormal.clone(),
        points: [],
        projectionCount: 0,
        projectionSum: 0,
      };
      groups.set(key, group);
    }

    group.points.push(a.clone(), b.clone(), c.clone());
    group.projectionCount += 3;
    group.projectionSum +=
      a.dot(horizontalNormal) +
      b.dot(horizontalNormal) +
      c.dot(horizontalNormal);
  }

  return Array.from(groups.values())
    .map((group) => createWallColliderFromFaceGroup(object, group, roomCenter))
    .filter(Boolean);
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

  roomModel.traverse((object) => {
    if (!isUsdWallMesh(object) || !object.geometry) return;

    object.geometry.computeBoundingBox();
    if (!object.geometry.boundingBox || object.geometry.boundingBox.isEmpty())
      return;

    const faceColliders = worldWallFaceCollidersFromGeometry(
      object,
      roomCenter,
    );

    if (faceColliders.length) {
      colliders.push(...faceColliders);
      return;
    }

    const wallObbs = worldWallObbsFromGeometry(object);
    if (!wallObbs.length) {
      wallObbs.push(
        worldObbFromLocalBox(object.geometry.boundingBox, object.matrixWorld),
      );
    }

    wallObbs.forEach((wallObb) => {
      const thinnestAxis =
        wallObb.halfSize.x <= wallObb.halfSize.y &&
        wallObb.halfSize.x <= wallObb.halfSize.z
          ? "x"
          : wallObb.halfSize.y <= wallObb.halfSize.z
            ? "y"
            : "z";
      const originalHalfThickness = wallObb.halfSize[thinnestAxis];
      const nextHalfThickness = originalHalfThickness;
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
      const wallCenterProjection = wallObb.center.dot(wallNormal);
      const roomSide =
        roomCenter.dot(wallNormal) >= wallCenterProjection ? 1 : -1;
      const roomFacingProjection =
        wallObb.center.dot(wallNormal) + roomSide * originalHalfThickness;
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

    if (!outlineGeometry && !baselineGeometry) return;

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
