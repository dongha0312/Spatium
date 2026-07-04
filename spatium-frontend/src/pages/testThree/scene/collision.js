import * as THREE from "three";
import { wallConfigNumber, wallSweepRotationStep } from "./sceneConfig";

const WALL_PARALLEL_RELAXATION = 0;
const WALL_ALIGNMENT_RELAXATION_ANGLE = Math.PI / 4;
const WALL_SLIDE_CONTACT_DISTANCE = 0.08;

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

export function applyInterpolatedTransform(object, from, to, t, scratch) {
  scratch.position.lerpVectors(from.position, to.position, t);
  scratch.quaternion.slerpQuaternions(from.quaternion, to.quaternion, t);
  scratch.scale.lerpVectors(from.scale, to.scale, t);

  object.position.copy(scratch.position);
  object.quaternion.copy(scratch.quaternion);
  object.scale.copy(scratch.scale);
  object.updateWorldMatrix(true, false);
}

export function adjustedMovementForWallSlide(movement, blockingWalls) {
  const adjusted = movement.clone();

  for (let pass = 0; pass < 4; pass += 1) {
    blockingWalls.forEach((wall) => {
      if (!wall.roomFacingNormal) return;

      const normalDistance = adjusted.dot(wall.roomFacingNormal);
      if (Math.abs(normalDistance) > 1e-10) {
        adjusted.addScaledVector(wall.roomFacingNormal, -normalDistance);
      }
    });
  }

  return adjusted;
}

export function tryApplyWallSlide(
  object,
  valid,
  target,
  blockingWalls,
  wallColliders,
) {
  if (!blockingWalls.length) return false;

  const movement = target.position.clone().sub(valid.position);
  if (movement.lengthSq() <= 1e-10) return false;

  object.position.copy(valid.position);
  object.quaternion.copy(valid.quaternion);
  object.scale.copy(valid.scale);
  object.updateWorldMatrix(true, false);

  const validObb = worldObbForObject(object);
  const contactWalls = blockingWalls.filter((wall) =>
    objectTouchesWallForSlide(validObb, wall),
  );
  if (!contactWalls.length) return false;

  const adjustedMovement = adjustedMovementForWallSlide(
    movement,
    contactWalls,
  );
  if (adjustedMovement.lengthSq() <= 1e-10) return false;

  object.position.copy(valid.position).add(adjustedMovement);
  object.quaternion.copy(target.quaternion);
  object.scale.copy(target.scale);
  object.updateWorldMatrix(true, false);

  if (!hasWallCollision(object, wallColliders)) {
    rememberValidTransform(object);
    return true;
  }

  const best = {
    position: valid.position.clone(),
    quaternion: valid.quaternion.clone(),
    scale: valid.scale.clone(),
  };
  let low = 0;
  let high = 1;

  for (let i = 0; i < wallConfigNumber("clampIterations"); i += 1) {
    const t = (low + high) / 2;
    object.position.copy(valid.position).addScaledVector(adjustedMovement, t);
    object.quaternion.copy(target.quaternion);
    object.scale.copy(target.scale);
    object.updateWorldMatrix(true, false);

    if (hasWallCollision(object, wallColliders)) {
      high = t;
    } else {
      low = t;
      best.position.copy(object.position);
      best.quaternion.copy(object.quaternion);
      best.scale.copy(object.scale);
    }
  }

  if (low > 1e-4) {
    object.position.copy(best.position);
    object.quaternion.copy(best.quaternion);
    object.scale.copy(best.scale);
    object.updateWorldMatrix(true, false);
    rememberValidTransform(object);
    return true;
  }

  object.position.copy(valid.position);
  object.quaternion.copy(valid.quaternion);
  object.scale.copy(valid.scale);
  object.updateWorldMatrix(true, false);
  return false;
}

export function clampObjectToWallBoundary(object, wallColliders) {
  if (object?.userData.ignoreWallConstraint && wallColliders.length) {
    const target = {
      position: object.position.clone(),
      quaternion: object.quaternion.clone(),
      scale: object.scale.clone(),
    };
    const targetIntersectsWalls = objectIntersectsWalls(object, wallColliders);

    if (!targetIntersectsWalls) {
      object.userData.ignoreWallConstraint = false;
      rememberValidTransform(object);
      return false;
    }

    const previous = {
      position: object.userData.lastValidPosition?.clone(),
      quaternion: object.userData.lastValidQuaternion?.clone(),
      scale: object.userData.lastValidScale?.clone(),
    };

    if (!previous.position || !previous.quaternion || !previous.scale) {
      rememberValidTransform(object);
      return false;
    }

    const targetPenetrations = wallBoundaryPenetrationsForObject(
      object,
      wallColliders,
    );

    object.position.copy(previous.position);
    object.quaternion.copy(previous.quaternion);
    object.scale.copy(previous.scale);
    object.updateWorldMatrix(true, false);
    const previousPenetrations = wallBoundaryPenetrationsForObject(
      object,
      wallColliders,
    );

    object.position.copy(target.position);
    object.quaternion.copy(target.quaternion);
    object.scale.copy(target.scale);
    object.updateWorldMatrix(true, false);

    if (
      wallBoundaryPenetrationDidNotIncrease(
        previousPenetrations,
        targetPenetrations,
      )
    ) {
      rememberValidTransform(object);
      return false;
    }

    object.position.copy(previous.position);
    object.quaternion.copy(previous.quaternion);
    object.scale.copy(previous.scale);
    object.updateWorldMatrix(true, false);
    return true;
  }

  if (!shouldConstrainToWalls(object) || !wallColliders.length) {
    rememberValidTransform(object);
    return false;
  }

  const valid = {
    position: object.userData.lastValidPosition?.clone(),
    quaternion: object.userData.lastValidQuaternion?.clone(),
    scale: object.userData.lastValidScale?.clone(),
  };
  const target = {
    position: object.position.clone(),
    quaternion: object.quaternion.clone(),
    scale: object.scale.clone(),
  };

  if (!valid.position || !valid.quaternion || !valid.scale) {
    if (hasWallCollision(object, wallColliders)) {
      restoreValidTransform(object);
      return true;
    }

    rememberValidTransform(object);
    return false;
  }

  object.position.copy(valid.position);
  object.quaternion.copy(valid.quaternion);
  object.scale.copy(valid.scale);
  object.updateWorldMatrix(true, false);

  if (hasWallCollision(object, wallColliders)) {
    restoreValidTransform(object);
    return true;
  }

  const scratch = {
    position: new THREE.Vector3(),
    quaternion: new THREE.Quaternion(),
    scale: new THREE.Vector3(),
  };
  const distance = valid.position.distanceTo(target.position);
  const angle = valid.quaternion.angleTo(target.quaternion);
  const sweepSteps = Math.min(
    wallConfigNumber("sweepMaxSteps"),
    Math.max(
      1,
      Math.ceil(distance / wallConfigNumber("sweepStep")),
      Math.ceil(angle / wallSweepRotationStep()),
    ),
  );
  let low = 0;
  let high = null;

  for (let i = 1; i <= sweepSteps; i += 1) {
    const t = i / sweepSteps;
    applyInterpolatedTransform(object, valid, target, t, scratch);

    if (hasWallCollision(object, wallColliders)) {
      high = t;
      break;
    }

    low = t;
  }

  if (high === null) {
    object.position.copy(target.position);
    object.quaternion.copy(target.quaternion);
    object.scale.copy(target.scale);
    object.updateWorldMatrix(true, false);
    rememberValidTransform(object);
    return false;
  }

  applyInterpolatedTransform(object, valid, target, high, scratch);
  if (
    tryApplyWallSlide(
      object,
      valid,
      target,
      getIntersectingWalls(object, wallColliders),
      wallColliders,
    )
  ) {
    return true;
  }

  const best = {
    position: valid.position.clone(),
    quaternion: valid.quaternion.clone(),
    scale: valid.scale.clone(),
  };

  for (let i = 0; i < wallConfigNumber("clampIterations"); i += 1) {
    const t = (low + high) / 2;
    applyInterpolatedTransform(object, valid, target, t, scratch);

    if (hasWallCollision(object, wallColliders)) {
      high = t;
    } else {
      low = t;
      best.position.copy(object.position);
      best.quaternion.copy(object.quaternion);
      best.scale.copy(object.scale);
    }
  }

  object.position.copy(best.position);
  object.quaternion.copy(best.quaternion);
  object.scale.copy(best.scale);
  object.updateWorldMatrix(true, false);
  rememberValidTransform(object);
  return true;
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
  });

  editableObjects.forEach((object) => {
    if (
      shouldCheckFurnitureCollision(object) &&
      objectIntersectsWalls(object, wallColliders)
    ) {
      object.userData.collisions.push("wall");
    }
  });

  editableObjects.forEach((object) =>
    setFurnitureVisualState(object, selectedObject),
  );
  return selectedObject?.userData.collisions || [];
}
