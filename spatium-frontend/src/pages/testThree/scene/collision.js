import * as THREE from "three";
import { wallConfigNumber, wallSweepRotationStep } from "./sceneConfig";

export function editableObjectLabel(object) {
  const item = object.userData.roomItem;
  return `${item.category || object.userData.category || "object"} ${
    object.userData.sourceIndex + 1
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

export function objectOverlapsWallSpan(objectObb, wall) {
  if (!wall.spanAxes?.length) return true;

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

  return (
    innerMostProjection <
    wall.roomFacingProjection - wallConfigNumber("boundaryEpsilon")
  );
}

export function wallBlocksObjectObb(objectObb, wall) {
  return objectObbViolatesWallBoundary(objectObb, wall);
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
    const startsInWallCollision = objectIntersectsWalls(object, wallColliders);
    object.userData.startsInWallCollision = startsInWallCollision;
    object.userData.ignoreWallConstraint = startsInWallCollision;
    rememberValidTransform(object);
  });
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

  for (let pass = 0; pass < 2; pass += 1) {
    blockingWalls.forEach((wall) => {
      if (!wall.roomFacingNormal) return;

      const intoRoomDistance = adjusted.dot(wall.roomFacingNormal);
      if (intoRoomDistance < 0) {
        adjusted.addScaledVector(wall.roomFacingNormal, -intoRoomDistance);
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

  const adjustedMovement = adjustedMovementForWallSlide(
    movement,
    blockingWalls,
  );
  if (adjustedMovement.distanceToSquared(movement) <= 1e-10) return false;

  object.position.copy(valid.position).add(adjustedMovement);
  object.quaternion.copy(target.quaternion);
  object.scale.copy(target.scale);
  object.updateWorldMatrix(true, false);

  if (!hasWallCollision(object, wallColliders)) {
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
    if (!objectIntersectsWalls(object, wallColliders)) {
      object.userData.ignoreWallConstraint = false;
      rememberValidTransform(object);
    }

    return false;
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

  const obbs = editableObjects
    .filter(shouldCheckFurnitureCollision)
    .map((object) => ({
      object,
      obb: worldObbForObject(object),
    }));

  for (let i = 0; i < obbs.length; i += 1) {
    for (let j = i + 1; j < obbs.length; j += 1) {
      if (!obbs[i].obb.intersectsOBB(obbs[j].obb, 0.0001)) continue;

      obbs[i].object.userData.collisions.push(
        editableObjectLabel(obbs[j].object),
      );
      obbs[j].object.userData.collisions.push(
        editableObjectLabel(obbs[i].object),
      );
    }
  }

  editableObjects.forEach((object) =>
    setFurnitureVisualState(object, selectedObject),
  );
  return selectedObject?.userData.collisions || [];
}
