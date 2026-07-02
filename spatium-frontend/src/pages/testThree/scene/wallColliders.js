import * as THREE from "three";
import { OBB } from "three/examples/jsm/math/OBB.js";
import { sceneColor, wallConfigNumber } from "./sceneConfig";

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

export function createWallColliderVisuals(wallColliders) {
  const group = new THREE.Group();
  group.name = "WallColliderDebugLayer";

  wallColliders.forEach((wall, index) => {
    const size = wall.obb.halfSize.clone().multiplyScalar(2);
    const geometry = new THREE.BoxGeometry(size.x, size.y, size.z);
    const rotationMatrix = new THREE.Matrix4().setFromMatrix3(
      wall.obb.rotation,
    );
    const fill = new THREE.Mesh(
      geometry,
      new THREE.MeshBasicMaterial({
        color: sceneColor("wallColliderDebug"),
        opacity: 0.18,
        transparent: true,
        depthTest: false,
        depthWrite: false,
      }),
    );
    const edge = new THREE.LineSegments(
      new THREE.EdgesGeometry(geometry),
      new THREE.LineBasicMaterial({
        color: sceneColor("wallColliderDebug"),
        transparent: true,
        opacity: 0.95,
        depthTest: false,
      }),
    );

    fill.name = `wall-collider-fill-${index + 1}`;
    edge.name = `wall-collider-edge-${index + 1}`;
    fill.position.copy(wall.obb.center);
    edge.position.copy(wall.obb.center);
    fill.quaternion.setFromRotationMatrix(rotationMatrix);
    edge.quaternion.setFromRotationMatrix(rotationMatrix);
    fill.renderOrder = 20;
    edge.renderOrder = 21;
    group.add(fill, edge);
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
