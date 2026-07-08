import * as THREE from "three";
import { optionalConfigBoolean, wallConfigNumber } from "./sceneConfig";

const WALL_PARALLEL_RELAXATION = 0;
const WALL_ALIGNMENT_RELAXATION_ANGLE = Math.PI / 4;
const WALL_SLIDE_CONTACT_DISTANCE = 0.08;
const WALL_MOVEMENT_MARGIN = 1e-4;

function vectorSummary(vector) {
  return {
    x: Number(vector.x.toFixed(4)),
    y: Number(vector.y.toFixed(4)),
    z: Number(vector.z.toFixed(4)),
  };
}

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
  return optionalConfigBoolean(["wallConstraints", "logWallDiagnostics"], true);
}

export function editableObjectLabel(object) {
  const item = object.userData.roomItem;
  return `${item.category || object.userData.category || "object"} ${object.userData.sourceIndex + 1
    }`;
}

export function canTransformObject(object) {
  return Boolean(object?.userData.editable);
}

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

export function restoreValidTransform(object) {
  if (!object?.userData.lastValidPosition) return;

  object.position.copy(object.userData.lastValidPosition);
  object.quaternion.copy(object.userData.lastValidQuaternion);
  object.scale.copy(object.userData.lastValidScale);
  object.updateWorldMatrix(true, false);
}

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

export function objectIntersectsWalls(object, wallColliders) {
  if (!object || !wallColliders.length) return false;

  const objectObb = worldObbForObject(object);
  return wallColliders.some((wall) => wallBlocksObjectObb(objectObb, wall));
}

export function getIntersectingWalls(object, wallColliders) {
  if (!object || !wallColliders.length) return [];

  const objectObb = worldObbForObject(object);
  return wallColliders.filter((wall) => wallBlocksObjectObb(objectObb, wall));
}

export function projectionRadiusForObb(obb, axis) {
  const xAxis = new THREE.Vector3();
  const yAxis = new THREE.Vector3();
  const zAxis = new THREE.Vector3();
  obb.rotation.extractBasis(xAxis, yAxis, zAxis);

  return (
    Math.abs(axis.dot(xAxis)) * obb.halfSize.x +
    Math.abs(axis.dot(yAxis)) * obb.halfSize.y +
    Math.abs(axis.dot(zAxis)) * obb.halfSize.z
  );
}

export function objectWallFaceNormalAngle(objectObb, wall) {
  if (!wall.roomFacingNormal) return Math.PI / 2;

  const normal = wall.roomFacingNormal.clone().normalize();
  const axes = [
    new THREE.Vector3(),
    new THREE.Vector3(),
    new THREE.Vector3(),
  ];
  objectObb.rotation.extractBasis(axes[0], axes[1], axes[2]);

  const bestAlignment = axes.reduce(
    (best, axis) => Math.max(best, Math.abs(axis.normalize().dot(normal))),
    0,
  );

  return Math.acos(THREE.MathUtils.clamp(bestAlignment, -1, 1));
}

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

function spanAxisByName(wall, name, fallbackIndex) {
  return (
    wall.spanAxes?.find((spanAxis) => spanAxis.name === name) ||
    wall.spanAxes?.[fallbackIndex]
  );
}

function cross2D(a, b, c) {
  return (
    (b.length - a.length) * (c.height - a.height) -
    (b.height - a.height) * (c.length - a.length)
  );
}

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

function projectedObbPolygon2D(objectObb, heightAxis, lengthAxis) {
  const xAxis = new THREE.Vector3();
  const yAxis = new THREE.Vector3();
  const zAxis = new THREE.Vector3();
  objectObb.rotation.extractBasis(xAxis, yAxis, zAxis);

  const projectedCorners = [];
  [-1, 1].forEach((xSign) => {
    [-1, 1].forEach((ySign) => {
      [-1, 1].forEach((zSign) => {
        const corner = objectObb.center
          .clone()
          .addScaledVector(xAxis, objectObb.halfSize.x * xSign)
          .addScaledVector(yAxis, objectObb.halfSize.y * ySign)
          .addScaledVector(zAxis, objectObb.halfSize.z * zSign);

        projectedCorners.push({
          height: corner.dot(heightAxis),
          length: corner.dot(lengthAxis),
        });
      });
    });
  });

  return convexHull2D(projectedCorners);
}

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

export function wallBoundaryPenetrationsForObject(object, wallColliders) {
  if (!object || !wallColliders.length) return [];

  const objectObb = worldObbForObject(object);
  return wallColliders.map((wall) =>
    objectWallBoundaryPenetration(objectObb, wall),
  );
}

export function wallBoundaryPenetrationDidNotIncrease(previous, next) {
  const tolerance = wallConfigNumber("boundaryEpsilon") + 1e-5;

  return next.every(
    (depth, index) => depth <= (previous[index] || 0) + tolerance,
  );
}

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

export function shouldCheckFurnitureCollision(object) {
  const category =
    object?.userData.roomItem?.category || object?.userData.category;
  return Boolean(
    object?.userData.editable && category !== "door" && category !== "window",
  );
}

export function hasWallCollision(object, wallColliders) {
  if (!shouldConstrainToWalls(object) || !wallColliders.length) return false;
  return objectIntersectsWalls(object, wallColliders);
}

export function initializeWallConstraints(editableObjects, wallColliders) {
  editableObjects.forEach((object) => {
    pushObjectOutOfWalls(object, wallColliders);
    object.userData.startsInWallCollision = false;
    object.userData.ignoreWallConstraint = false;
    rememberValidTransform(object);
  });
}

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

function wallSolidClearance(objectObb, wall) {
  const axes = [
    new THREE.Vector3(),
    new THREE.Vector3(),
    new THREE.Vector3(),
  ];
  const halfSizes = [
    wall.obb.halfSize.x,
    wall.obb.halfSize.y,
    wall.obb.halfSize.z,
  ];
  const thicknessIndex =
    halfSizes[0] <= halfSizes[1] && halfSizes[0] <= halfSizes[2]
      ? 0
      : halfSizes[1] <= halfSizes[2]
        ? 1
        : 2;

  wall.obb.rotation.extractBasis(axes[0], axes[1], axes[2]);

  const axis = axes[thicknessIndex].normalize();
  const offset = objectObb.center.clone().sub(wall.obb.center);
  const normal = axis.multiplyScalar(offset.dot(axis) >= 0 ? 1 : -1);
  const objectRadius = projectionRadiusForObb(objectObb, normal);
  const clearance =
    Math.abs(offset.dot(axis)) - halfSizes[thicknessIndex] - objectRadius;

  return { normal, clearance };
}

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

  for (let pass = 0; pass < 4; pass += 1) {
    let changed = false;

    wallColliders.forEach((wall) => {
      if (!wall.roomFacingNormal || !Number.isFinite(wall.roomFacingProjection)) {
        return;
      }

      const movedObb = objectObb.clone();
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
      const movedObb = objectObb.clone();
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
  const stepCount = Math.max(1, Math.ceil(totalDistance / stepSize));
  const requestedStep = movement.clone().multiplyScalar(1 / stepCount);
  const objectObb = worldObbForObject(object);
  const constrained = new THREE.Vector3();
  const blockedWalls = [];
  const blockedWallSet = new Set();

  object.userData.blockedWallColliders = blockedWalls;

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
      wallColliders,
      rememberBlockedWall,
    );

    if (adjustedStep.lengthSq() <= 1e-10) break;

    objectObb.center.add(adjustedStep);
    constrained.add(adjustedStep);
  }

  return constrained;
}

export function setFurnitureVisualState(object, selectedObject) {
  const isSelected = object === selectedObject;
  const hasCollision = (object.userData.collisions || []).length > 0;
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
