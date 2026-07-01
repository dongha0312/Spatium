import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { USDLoader } from "three/examples/jsm/loaders/USDLoader.js";
import { OBB } from "three/examples/jsm/math/OBB.js";
import {
  CSS2DObject,
  CSS2DRenderer,
} from "three/examples/jsm/renderers/CSS2DRenderer.js";
import "./TestThreeStagingPage.css";

const SCENE_CONFIG_URL = "/config/test-three-scene-config.json";
let sceneConfig = null;

async function loadSceneConfig() {
  const response = await fetch(SCENE_CONFIG_URL);
  if (!response.ok) {
    throw new Error(`Failed to load scene config (${response.status})`);
  }

  sceneConfig = await response.json();
  return sceneConfig;
}

function requiredConfigValue(path) {
  if (!sceneConfig) {
    throw new Error("Scene config has not been loaded.");
  }

  const value = path.reduce((current, key) => current?.[key], sceneConfig);
  if (value == null) {
    throw new Error(`Missing scene config value: ${path.join(".")}`);
  }
  return value;
}

function configNumber(path) {
  const value = Number(requiredConfigValue(path));
  if (!Number.isFinite(value)) {
    throw new Error(`Scene config value must be a number: ${path.join(".")}`);
  }
  return value;
}

function configBoolean(path) {
  return Boolean(requiredConfigValue(path));
}

function configString(path) {
  return String(requiredConfigValue(path));
}

function getRoomModelUrl() {
  return configString(["room", "modelUrl"]);
}

function getRoomMetadataUrl() {
  return configString(["room", "metadataUrl"]);
}

function getModelUrls() {
  return { ...requiredConfigValue(["models"]) };
}

function sceneColor(name) {
  return configString(["colors", name]);
}

function referenceFallbackThickness(category) {
  return configNumber(["referenceFallbackThickness", category]);
}

function wallConfigNumber(name) {
  return configNumber(["wallConstraints", name]);
}

function wallConfigBoolean(name) {
  return configBoolean(["wallConstraints", name]);
}

function wallSweepRotationStep() {
  return THREE.MathUtils.degToRad(wallConfigNumber("sweepRotationStepDegrees"));
}

function normalizeModelKey(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

function loadUsdRoomModel(url) {
  if (!url) return Promise.resolve(null);

  return new Promise((resolve) => {
    new USDLoader().load(url, resolve, undefined, () => resolve(null));
  });
}

function loadGltfModel(url, label) {
  if (!url) {
    return Promise.reject(new Error(`Missing model URL for ${label}.`));
  }

  return new Promise((resolve, reject) => {
    new GLTFLoader().load(url, resolve, undefined, reject);
  });
}

function modelEntriesForCategories(categories) {
  const entries = Object.entries(getModelUrls()).filter(([, url]) => url);
  if (!categories) return entries;

  const selectedEntries = new Map();
  categories.forEach((category) => {
    const normalizedCategory = normalizeModelKey(category);
    const matchedEntry = entries.find(
      ([key]) => normalizeModelKey(key) === normalizedCategory,
    );
    if (matchedEntry) {
      selectedEntries.set(normalizeModelKey(matchedEntry[0]), matchedEntry);
    }
  });

  return Array.from(selectedEntries.values());
}

function modelCategoriesFromMetadata(metadata) {
  const categories = new Set(
    (metadata.objects || [])
      .map((item) => item.category)
      .filter(Boolean),
  );

  if ((metadata.doors || []).length) categories.add("door");
  if ((metadata.windows || []).length) categories.add("window");

  return Array.from(categories);
}

async function loadModelTemplates(categories) {
  const entries = modelEntriesForCategories(categories);
  const loadedTemplates = await Promise.all(
    entries.map(async ([key, url]) => ({
      key,
      lookupKey: normalizeModelKey(key),
      gltf: await loadGltfModel(url, key),
    })),
  );

  return new Map(
    loadedTemplates.map((template) => [template.lookupKey, template]),
  );
}

function findModelTemplate(modelTemplates, category) {
  return modelTemplates.get(normalizeModelKey(category)) || null;
}

function requireModelTemplate(modelTemplates, category) {
  const template = findModelTemplate(modelTemplates, category);
  if (!template) {
    throw new Error(
      `Missing model mapping for "${category}" in ${SCENE_CONFIG_URL}.`,
    );
  }
  return template;
}

function fetchJson(url, label) {
  if (!url) {
    return Promise.reject(new Error(`Missing JSON URL for ${label}.`));
  }

  return fetch(url).then((response) => {
    if (!response.ok) {
      throw new Error(`Failed to load ${label} (${response.status})`);
    }
    return response.json();
  });
}

function cloneJsonValue(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

function downloadJsonFile(filename, data) {
  const blob = new Blob([JSON.stringify(data, null, 2)], {
    type: "application/json",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");

  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function matrixFromColumns(columns) {
  const matrix = new THREE.Matrix4();
  matrix.fromArray(columns.flat());
  return matrix;
}

function columnsFromMatrix(matrix) {
  const values = matrix.toArray();
  return [
    values.slice(0, 4),
    values.slice(4, 8),
    values.slice(8, 12),
    values.slice(12, 16),
  ];
}

function createLabel(text, className = "furniture-label") {
  const div = document.createElement("div");
  div.className = className;
  div.textContent = text;
  return new CSS2DObject(div);
}

function disposeMaterial(material) {
  Object.values(material).forEach((value) => {
    if (
      value &&
      typeof value === "object" &&
      typeof value.dispose === "function"
    ) {
      value.dispose();
    }
  });
  material.dispose();
}

function disposeScene(scene) {
  scene.traverse((object) => {
    if (object.geometry) object.geometry.dispose();
    if (object.material) {
      if (Array.isArray(object.material)) {
        object.material.forEach(disposeMaterial);
      } else {
        disposeMaterial(object.material);
      }
    }
  });
}

function frameObject(camera, controls, object) {
  const bounds = new THREE.Box3().setFromObject(object);
  if (bounds.isEmpty()) return;

  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const maxDimension = Math.max(size.x, size.y, size.z, 1);
  const distance =
    (maxDimension / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2))) *
    1.35;

  camera.position
    .copy(center)
    .add(new THREE.Vector3(0.7, 0.45, 1).normalize().multiplyScalar(distance));
  camera.near = Math.max(distance / 1000, 0.01);
  camera.far = distance * 100;
  camera.updateProjectionMatrix();
  controls.target.copy(center);
  controls.update();
}

function categoryColor(category) {
  const categoryColors = requiredConfigValue(["colors", "category"]);
  const normalizedCategory = normalizeModelKey(category);
  const matchedEntry = Object.entries(categoryColors).find(
    ([key]) => normalizeModelKey(key) === normalizedCategory,
  );
  return matchedEntry?.[1] || configString(["colors", "category", "object"]);
}

function decomposeRoomTransform(item) {
  const position = new THREE.Vector3();
  const quaternion = new THREE.Quaternion();
  const scale = new THREE.Vector3();
  matrixFromColumns(item.transform.columns).decompose(
    position,
    quaternion,
    scale,
  );
  return { position, quaternion, scale };
}

function objectToEditableJson(object) {
  object.updateMatrix();
  const item = object.userData.roomItem;
  const sourceType = object.userData.sourceType || "object";
  const sourceIndex = object.userData.sourceIndex;
  const collisions = object.userData.collisions || [];
  const matrix = new THREE.Matrix4().compose(
    object.position,
    object.quaternion,
    object.scale,
  );
  const rotation = new THREE.Euler().setFromQuaternion(object.quaternion);

  return {
    id: `${sourceType}-${sourceIndex}`,
    sourceType,
    index: sourceIndex,
    category: item.category || object.userData.category || "object",
    dimensions: item.dimensions,
    position: {
      x: Number(object.position.x.toFixed(4)),
      y: Number(object.position.y.toFixed(4)),
      z: Number(object.position.z.toFixed(4)),
    },
    rotation: {
      x: Number(rotation.x.toFixed(4)),
      y: Number(rotation.y.toFixed(4)),
      z: Number(rotation.z.toFixed(4)),
    },
    transform: {
      columns: columnsFromMatrix(matrix).map((column) =>
        column.map((value) => Number(value.toFixed(6))),
      ),
    },
    collision: {
      hasCollision: collisions.length > 0,
      with: collisions,
    },
  };
}

function roundedNumber(value, digits = 6) {
  return Number(Number(value).toFixed(digits));
}

function roundedArray(values, digits = 6) {
  return Array.from(values, (value) => roundedNumber(value, digits));
}

function materialToRoomJson(material) {
  const sourceMaterial = Array.isArray(material) ? material[0] : material;
  const color = sourceMaterial?.color?.getHexString
    ? `#${sourceMaterial.color.getHexString()}`
    : sceneColor("roomMaterialDefault");

  return {
    color,
    opacity: roundedNumber(sourceMaterial?.opacity ?? 1, 4),
    transparent: Boolean(sourceMaterial?.transparent),
    side: sourceMaterial?.side ?? THREE.FrontSide,
    roughness: roundedNumber(sourceMaterial?.roughness ?? 0.72, 4),
    metalness: roundedNumber(sourceMaterial?.metalness ?? 0, 4),
  };
}

function serializeRoomMesh(object) {
  const geometry = object.geometry;
  const position = geometry?.attributes?.position;
  if (!position) return null;

  const normal = geometry.attributes.normal;
  const uv = geometry.attributes.uv;
  const isWall = isUsdWallMesh(object);
  const isFloor = isUsdFloorMesh(object);
  const type = isWall ? "wall" : isFloor ? "floor" : "mesh";
  object.updateWorldMatrix(true, false);

  return {
    name: object.name || "room-mesh",
    type,
    isWall,
    isFloor,
    matrix: {
      columns: columnsFromMatrix(object.matrixWorld).map((column) =>
        column.map((value) => roundedNumber(value)),
      ),
    },
    geometry: {
      position: roundedArray(position.array),
      normal: normal ? roundedArray(normal.array) : null,
      uv: uv ? roundedArray(uv.array) : null,
      index: geometry.index ? Array.from(geometry.index.array) : null,
    },
    material: materialToRoomJson(object.material),
  };
}

function serializeRoomModelToJson(roomModel) {
  if (!roomModel) return null;

  const walls = [];
  const floors = [];
  const meshes = [];
  roomModel.updateWorldMatrix(true, true);
  roomModel.traverse((object) => {
    if (!object.isMesh || !object.geometry || !object.visible) return;
    if (isUsdReplacedMesh(object)) return;

    const mesh = serializeRoomMesh(object);
    if (!mesh) return;

    if (mesh.type === "wall") {
      walls.push(mesh);
    } else if (mesh.type === "floor") {
      floors.push(mesh);
    } else {
      meshes.push(mesh);
    }
  });

  return {
    version: 1,
    coordinateSystem: "three-world",
    generatedFrom: getRoomModelUrl(),
    walls,
    floors,
    meshes,
  };
}

function roomMeshesFromJson(roomJson) {
  if (!roomJson) return [];

  const walls = Array.isArray(roomJson.walls)
    ? roomJson.walls.map((mesh) => ({
        ...mesh,
        type: mesh.type || "wall",
        isWall: mesh.isWall ?? true,
      }))
    : [];
  const floors = Array.isArray(roomJson.floors)
    ? roomJson.floors.map((mesh) => ({
        ...mesh,
        type: mesh.type || "floor",
        isFloor: mesh.isFloor ?? true,
      }))
    : [];
  const meshes = Array.isArray(roomJson.meshes) ? roomJson.meshes : [];

  return walls.length || floors.length
    ? [...walls, ...floors, ...meshes]
    : meshes;
}

function createRoomModelFromJson(roomJson) {
  const roomMeshes = roomMeshesFromJson(roomJson);
  if (!roomMeshes.length) return null;

  const group = new THREE.Group();
  group.name = "JsonRoomLayer";

  roomMeshes.forEach((meshData, index) => {
    const positions = meshData.geometry?.position;
    if (!positions?.length) return;

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute(
      "position",
      new THREE.BufferAttribute(new Float32Array(positions), 3),
    );

    if (meshData.geometry.normal?.length) {
      geometry.setAttribute(
        "normal",
        new THREE.BufferAttribute(
          new Float32Array(meshData.geometry.normal),
          3,
        ),
      );
    }

    if (meshData.geometry.uv?.length) {
      geometry.setAttribute(
        "uv",
        new THREE.BufferAttribute(new Float32Array(meshData.geometry.uv), 2),
      );
    }

    if (meshData.geometry.index?.length) {
      geometry.setIndex(meshData.geometry.index);
    }

    if (!geometry.attributes.normal) {
      geometry.computeVertexNormals();
    }

    const materialData = meshData.material || {};
    const material = new THREE.MeshStandardMaterial({
      color: materialData.color || sceneColor("roomMaterialDefault"),
      opacity: materialData.opacity ?? 1,
      transparent: Boolean(
        materialData.transparent || materialData.opacity < 1,
      ),
      roughness: materialData.roughness ?? 0.72,
      metalness: materialData.metalness ?? 0,
      side: materialData.side ?? THREE.FrontSide,
    });
    const mesh = new THREE.Mesh(geometry, material);

    mesh.name = meshData.name || `json-room-mesh-${index + 1}`;
    mesh.matrix.copy(matrixFromColumns(meshData.matrix.columns));
    mesh.matrixAutoUpdate = false;
    mesh.castShadow = false;
    mesh.receiveShadow = true;
    mesh.userData.isUsdWallMesh = Boolean(
      meshData.isWall || meshData.type === "wall",
    );
    mesh.userData.isUsdFloorMesh = Boolean(
      meshData.isFloor || meshData.type === "floor",
    );
    group.add(mesh);
  });

  return group.children.length ? group : null;
}

function createReplayableMetadataJson(metadata, editedItems, roomModel) {
  const nextMetadata = cloneJsonValue(metadata) || {};
  const editsByObjectIndex = new Map(
    editedItems
      .filter((item) => item.sourceType === "object")
      .map((item) => [item.index, item]),
  );

  nextMetadata.objects = (nextMetadata.objects || []).map((item, index) => {
    const edit = editsByObjectIndex.get(index);
    if (!edit) return item;

    return {
      ...item,
      category: edit.category,
      dimensions: edit.dimensions,
      transform: edit.transform,
    };
  });

  nextMetadata.doors = nextMetadata.doors || [];
  nextMetadata.windows = nextMetadata.windows || [];
  nextMetadata._spatiumRoom =
    serializeRoomModelToJson(roomModel) || nextMetadata._spatiumRoom || null;
  nextMetadata._spatiumExport = {
    version: 1,
    exportedAt: new Date().toISOString(),
    source: {
      roomModelUrl: getRoomModelUrl(),
      roomMetadataUrl: getRoomMetadataUrl(),
      sceneConfigUrl: SCENE_CONFIG_URL,
      modelUrls: getModelUrls(),
    },
    editedItems,
  };

  return nextMetadata;
}

function editableObjectLabel(object) {
  const item = object.userData.roomItem;
  return `${item.category || object.userData.category || "object"} ${
    object.userData.sourceIndex + 1
  }`;
}

function canTransformObject(object) {
  return Boolean(object?.userData.editable);
}

function worldObbForObject(object) {
  object.updateWorldMatrix(true, false);
  return object.userData.localObb.clone().applyMatrix4(object.matrixWorld);
}

function rememberValidTransform(object) {
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

function restoreValidTransform(object) {
  if (!object?.userData.lastValidPosition) return;

  object.position.copy(object.userData.lastValidPosition);
  object.quaternion.copy(object.userData.lastValidQuaternion);
  object.scale.copy(object.userData.lastValidScale);
  object.updateWorldMatrix(true, false);
}

function shouldConstrainToWalls(object) {
  const category =
    object?.userData.roomItem?.category || object?.userData.category;
  return Boolean(
    object?.userData.editable &&
    !object.userData.ignoreWallConstraint &&
    category !== "door" &&
    category !== "window",
  );
}

function objectIntersectsWalls(object, wallColliders) {
  if (!object || !wallColliders.length) return false;

  const objectObb = worldObbForObject(object);
  return wallColliders.some((wall) => wallBlocksObjectObb(objectObb, wall));
}

function getIntersectingWalls(object, wallColliders) {
  if (!object || !wallColliders.length) return [];

  const objectObb = worldObbForObject(object);
  return wallColliders.filter((wall) => wallBlocksObjectObb(objectObb, wall));
}

function projectionRadiusForObb(obb, axis) {
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

function objectOverlapsWallSpan(objectObb, wall) {
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

function objectObbViolatesWallBoundary(objectObb, wall) {
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

function wallBlocksObjectObb(objectObb, wall) {
  return (
    objectObb.intersectsOBB(wall.obb, wallConfigNumber("collisionEpsilon")) ||
    objectObbViolatesWallBoundary(objectObb, wall)
  );
}

function shouldCheckFurnitureCollision(object) {
  const category =
    object?.userData.roomItem?.category || object?.userData.category;
  return Boolean(
    object?.userData.editable && category !== "door" && category !== "window",
  );
}

function hasWallCollision(object, wallColliders) {
  if (!shouldConstrainToWalls(object) || !wallColliders.length) return false;
  return objectIntersectsWalls(object, wallColliders);
}

function initializeWallConstraints(editableObjects, wallColliders) {
  editableObjects.forEach((object) => {
    const startsInWallCollision = objectIntersectsWalls(object, wallColliders);
    object.userData.startsInWallCollision = startsInWallCollision;
    object.userData.ignoreWallConstraint = startsInWallCollision;
    rememberValidTransform(object);
  });
}

function applyInterpolatedTransform(object, from, to, t, scratch) {
  scratch.position.lerpVectors(from.position, to.position, t);
  scratch.quaternion.slerpQuaternions(from.quaternion, to.quaternion, t);
  scratch.scale.lerpVectors(from.scale, to.scale, t);

  object.position.copy(scratch.position);
  object.quaternion.copy(scratch.quaternion);
  object.scale.copy(scratch.scale);
  object.updateWorldMatrix(true, false);
}

function adjustedMovementForWallSlide(movement, blockingWalls) {
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

function tryApplyWallSlide(
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

function clampObjectToWallBoundary(object, wallColliders) {
  if (object?.userData.ignoreWallConstraint && wallColliders.length) {
    if (!objectIntersectsWalls(object, wallColliders)) {
      object.userData.ignoreWallConstraint = false;
    }

    rememberValidTransform(object);
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

function setFurnitureVisualState(object, selectedObject) {
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

function refreshCollisionState(
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

function createEditableFurniture(item, index) {
  const dimensions = item.dimensions || {};
  const category = item.category || "object";
  const color = categoryColor(category);
  const width = Math.max(dimensions.x || 0.1, 0.04);
  const height = Math.max(dimensions.y || 0.1, 0.04);
  const depth = Math.max(dimensions.z || 0.1, 0.04);
  const geometry = new THREE.BoxGeometry(width, height, depth);
  const material = new THREE.MeshStandardMaterial({
    color,
    opacity: 0.72,
    transparent: true,
    roughness: 0.72,
  });
  const mesh = new THREE.Mesh(geometry, material);
  const edge = new THREE.LineSegments(
    new THREE.EdgesGeometry(geometry),
    new THREE.LineBasicMaterial({
      color: sceneColor("defaultEdge"),
      transparent: true,
      opacity: 0.5,
    }),
  );
  const root = new THREE.Group();
  const transform = decomposeRoomTransform(item);
  const label = createLabel(`${category} ${index + 1}`);

  root.name = `${category}-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);
  root.userData = {
    editable: true,
    roomItem: item,
    sourceType: "object",
    sourceIndex: index,
    localObb: new OBB(
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(width / 2, height / 2, depth / 2),
    ),
    visualMesh: mesh,
    edgeLine: edge,
    baseColor: new THREE.Color(color),
    collisionFillColor: new THREE.Color(sceneColor("collisionFill")),
    collisionColor: new THREE.Color(sceneColor("collision")),
    baseEdgeColor: new THREE.Color(sceneColor("defaultEdge")),
    selectedEdgeColor: new THREE.Color(sceneColor("selectedEdge")),
    collisions: [],
    initialPosition: transform.position.clone(),
    initialQuaternion: transform.quaternion.clone(),
    initialScale: transform.scale.clone(),
    lastValidPosition: transform.position.clone(),
    lastValidQuaternion: transform.quaternion.clone(),
    lastValidScale: transform.scale.clone(),
  };

  mesh.castShadow = true;
  mesh.receiveShadow = true;
  mesh.userData.editableRoot = root;
  edge.userData.editableRoot = root;
  label.position.set(0, (dimensions.y || 0.1) / 2 + 0.12, 0);

  root.add(mesh, edge, label);
  return { root, pickTargets: [mesh] };
}

function getBaseGeometryBounds(object) {
  const bounds = new THREE.Box3();
  const vertex = new THREE.Vector3();

  object.updateWorldMatrix(true, true);
  object.traverse((child) => {
    const position = child.geometry?.attributes?.position;
    if (!child.isMesh || !position) return;

    child.updateWorldMatrix(true, false);
    for (let i = 0; i < position.count; i += 1) {
      vertex.fromBufferAttribute(position, i).applyMatrix4(child.matrixWorld);
      bounds.expandByPoint(vertex);
    }
  });

  return bounds.isEmpty() ? new THREE.Box3().setFromObject(object) : bounds;
}

function fitModelToTargetSize(model, targetSize) {
  model.updateWorldMatrix(true, true);
  const bounds = getBaseGeometryBounds(model);
  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const scale = new THREE.Vector3(
    size.x > 0 ? targetSize.x / size.x : 1,
    size.y > 0 ? targetSize.y / size.y : 1,
    size.z > 0 ? targetSize.z / size.z : 1,
  );

  model.scale.multiply(scale);
  model.position.sub(center.multiply(scale));
  model.updateWorldMatrix(true, true);
}

function createEditableFurnitureModel(modelTemplate, item, index) {
  const dimensions = item.dimensions || {};
  const category = item.category || "object";
  const targetSize = new THREE.Vector3(
    Math.max(dimensions.x || 0.1, 0.04),
    Math.max(dimensions.y || 0.1, 0.04),
    Math.max(dimensions.z || 0.1, 0.04),
  );
  const root = new THREE.Group();
  const model = modelTemplate.clone(true);
  const transform = decomposeRoomTransform(item);
  const label = createLabel(`${category} ${index + 1}`);
  const hitGeometry = new THREE.BoxGeometry(
    targetSize.x,
    targetSize.y,
    targetSize.z,
  );
  const hitBox = new THREE.Mesh(
    hitGeometry,
    new THREE.MeshBasicMaterial({
      color: categoryColor(category),
      opacity: 0.001,
      transparent: true,
      depthWrite: false,
    }),
  );
  const edge = new THREE.LineSegments(
    new THREE.EdgesGeometry(hitGeometry),
    new THREE.LineBasicMaterial({
      color: sceneColor("defaultEdge"),
      transparent: true,
      opacity: 0.55,
    }),
  );

  root.name = `${category}-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);
  root.userData = {
    editable: true,
    roomItem: item,
    sourceType: "object",
    sourceIndex: index,
    localObb: new OBB(
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(targetSize.x / 2, targetSize.y / 2, targetSize.z / 2),
    ),
    edgeLine: edge,
    baseEdgeColor: new THREE.Color(sceneColor("defaultEdge")),
    selectedEdgeColor: new THREE.Color(sceneColor("selectedEdge")),
    collisionColor: new THREE.Color(sceneColor("collision")),
    collisions: [],
    initialPosition: transform.position.clone(),
    initialQuaternion: transform.quaternion.clone(),
    initialScale: transform.scale.clone(),
    lastValidPosition: transform.position.clone(),
    lastValidQuaternion: transform.quaternion.clone(),
    lastValidScale: transform.scale.clone(),
  };

  model.traverse((object) => {
    if (object.isMesh) {
      object.castShadow = true;
      object.receiveShadow = true;
      object.userData.editableRoot = root;
    }
  });

  fitModelToTargetSize(model, targetSize);
  hitBox.userData.editableRoot = root;
  edge.userData.editableRoot = root;
  label.position.set(0, targetSize.y / 2 + 0.12, 0);

  root.add(model, hitBox, edge, label);
  return { root, pickTargets: [hitBox] };
}

function createDoorModel(doorTemplate, item, index) {
  const doorItem = { ...item, category: "door" };
  const dimensions = item.dimensions || {};
  const fallbackThickness = referenceFallbackThickness("door");
  const targetSize = new THREE.Vector3(
    Math.max(dimensions.x || 0.1, 0.04),
    Math.max(dimensions.y || 0.1, 0.04),
    Math.max(dimensions.z || fallbackThickness, fallbackThickness),
  );
  const root = new THREE.Group();
  const model = doorTemplate.clone(true);
  const transform = decomposeRoomTransform(item);
  const label = createLabel(`door ${index + 1}`, "reference-label");
  const hitGeometry = new THREE.BoxGeometry(
    targetSize.x,
    targetSize.y,
    targetSize.z,
  );
  const hitBox = new THREE.Mesh(
    hitGeometry,
    new THREE.MeshBasicMaterial({
      color: sceneColor("doorReference"),
      opacity: 0.001,
      transparent: true,
      depthWrite: false,
    }),
  );
  const edge = new THREE.LineSegments(
    new THREE.EdgesGeometry(hitGeometry),
    new THREE.LineBasicMaterial({
      color: sceneColor("defaultEdge"),
      transparent: true,
      opacity: 0.55,
    }),
  );

  root.name = `door-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);
  root.userData = {
    editable: false,
    category: "door",
    roomItem: doorItem,
    sourceType: "door",
    sourceIndex: index,
    localObb: new OBB(
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(targetSize.x / 2, targetSize.y / 2, targetSize.z / 2),
    ),
    edgeLine: edge,
    baseEdgeColor: new THREE.Color(sceneColor("defaultEdge")),
    selectedEdgeColor: new THREE.Color(sceneColor("selectedEdge")),
    collisionColor: new THREE.Color(sceneColor("collision")),
    collisions: [],
    initialPosition: transform.position.clone(),
    initialQuaternion: transform.quaternion.clone(),
    initialScale: transform.scale.clone(),
    lastValidPosition: transform.position.clone(),
    lastValidQuaternion: transform.quaternion.clone(),
    lastValidScale: transform.scale.clone(),
  };

  model.traverse((object) => {
    if (object.isMesh) {
      object.castShadow = true;
      object.receiveShadow = true;
      object.userData.editableRoot = root;
    }
  });

  fitModelToTargetSize(model, targetSize);
  hitBox.userData.editableRoot = root;
  edge.userData.editableRoot = root;
  label.position.set(0, targetSize.y / 2 + 0.12, 0);

  root.add(model, hitBox, edge, label);
  return { root, pickTargets: [hitBox] };
}

function createWindowModel(windowTemplate, item, index) {
  const windowItem = { ...item, category: "window" };
  const dimensions = item.dimensions || {};
  const fallbackThickness = referenceFallbackThickness("window");
  const targetSize = new THREE.Vector3(
    Math.max(dimensions.x || 0.1, 0.04),
    Math.max(dimensions.y || 0.1, 0.04),
    Math.max(dimensions.z || fallbackThickness, fallbackThickness),
  );
  const root = new THREE.Group();
  const model = windowTemplate.clone(true);
  const transform = decomposeRoomTransform(item);
  const label = createLabel(`window ${index + 1}`, "reference-label");
  const hitGeometry = new THREE.BoxGeometry(
    targetSize.x,
    targetSize.y,
    targetSize.z,
  );
  const hitBox = new THREE.Mesh(
    hitGeometry,
    new THREE.MeshBasicMaterial({
      color: sceneColor("windowReference"),
      opacity: 0.001,
      transparent: true,
      depthWrite: false,
    }),
  );
  const edge = new THREE.LineSegments(
    new THREE.EdgesGeometry(hitGeometry),
    new THREE.LineBasicMaterial({
      color: sceneColor("defaultEdge"),
      transparent: true,
      opacity: 0.55,
    }),
  );

  root.name = `window-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);
  root.userData = {
    editable: false,
    category: "window",
    roomItem: windowItem,
    sourceType: "window",
    sourceIndex: index,
    localObb: new OBB(
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(targetSize.x / 2, targetSize.y / 2, targetSize.z / 2),
    ),
    edgeLine: edge,
    baseEdgeColor: new THREE.Color(sceneColor("defaultEdge")),
    selectedEdgeColor: new THREE.Color(sceneColor("selectedEdge")),
    collisionColor: new THREE.Color(sceneColor("collision")),
    collisions: [],
    initialPosition: transform.position.clone(),
    initialQuaternion: transform.quaternion.clone(),
    initialScale: transform.scale.clone(),
    lastValidPosition: transform.position.clone(),
    lastValidQuaternion: transform.quaternion.clone(),
    lastValidScale: transform.scale.clone(),
  };

  model.traverse((object) => {
    if (object.isMesh) {
      object.castShadow = true;
      object.receiveShadow = true;
      object.userData.editableRoot = root;
    }
  });

  fitModelToTargetSize(model, targetSize);
  hitBox.userData.editableRoot = root;
  edge.userData.editableRoot = root;
  label.position.set(0, targetSize.y / 2 + 0.12, 0);

  root.add(model, hitBox, edge, label);
  return { root, pickTargets: [hitBox] };
}

function isUsdReplacedMesh(object) {
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

function isUsdWallMesh(object) {
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

function isUsdFloorMesh(object) {
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

function worldObbFromLocalBox(box, matrixWorld) {
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

function geometryProjectionRange(object, direction) {
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

function createWallColliders(roomModel) {
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

function createWallColliderVisuals(wallColliders) {
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

function prepareRoomModel(model) {
  model.traverse((object) => {
    if (!object.isMesh) return;
    object.receiveShadow = true;

    if (isUsdReplacedMesh(object)) {
      object.visible = false;
    }
  });
}

export default function TestThreeStagingPage() {
  const containerRef = useRef(null);
  const selectedObjectRef = useRef(null);
  const syncSelectedRef = useRef(null);
  const sourceMetadataRef = useRef(null);
  const roomModelRef = useRef(null);
  const [isSceneConfigReady, setSceneConfigReady] = useState(
    Boolean(sceneConfig),
  );
  const [status, setStatus] = useState("Loading room model...");
  const [error, setError] = useState("");
  const [selectedItem, setSelectedItem] = useState(null);
  const [editedItems, setEditedItems] = useState([]);
  const [collisionSummary, setCollisionSummary] = useState({
    hasCollision: false,
    with: [],
  });
  const canResetSelected = selectedItem?.sourceType === "object";
  const canSaveJson = Boolean(sourceMetadataRef.current);

  function updateEditedItem(object) {
    const nextItem = objectToEditableJson(object);
    setSelectedItem(nextItem);
    setEditedItems((items) =>
      items.map((item) => (item.id === nextItem.id ? nextItem : item)),
    );
  }

  function resetSelectedObject() {
    const object = selectedObjectRef.current;
    if (!object) return;

    object.position.copy(object.userData.initialPosition);
    object.quaternion.copy(object.userData.initialQuaternion);
    object.scale.copy(object.userData.initialScale);
    object.userData.ignoreWallConstraint = Boolean(
      object.userData.startsInWallCollision,
    );
    rememberValidTransform(object);
    if (syncSelectedRef.current) {
      syncSelectedRef.current();
    } else {
      updateEditedItem(object);
    }
  }

  function saveEditedSceneJson() {
    const replayableMetadata = createReplayableMetadataJson(
      sourceMetadataRef.current,
      editedItems,
      roomModelRef.current,
    );
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");

    downloadJsonFile(
      `spatium-room-edited-${timestamp}.json`,
      replayableMetadata,
    );
  }

  useEffect(() => {
    if (!containerRef.current) return undefined;

    let isMounted = true;

    if (!isSceneConfigReady || !sceneConfig) {
      setError("");
      setStatus("Loading scene config...");
      loadSceneConfig()
        .then(() => {
          if (isMounted) {
            setSceneConfigReady(true);
          }
        })
        .catch((caughtError) => {
          if (!isMounted) return;
          setStatus("");
          setError(
            caughtError instanceof Error
              ? caughtError.message
              : String(caughtError),
          );
        });

      return () => {
        isMounted = false;
      };
    }

    let frameId = 0;
    const editableRoots = [];
    const pickTargets = [];
    const wallColliders = [];
    const root = containerRef.current;
    const width = root.clientWidth || window.innerWidth;
    const height = root.clientHeight || window.innerHeight;

    root.replaceChildren();
    setError("");
    setSelectedItem(null);
    setEditedItems([]);
    setCollisionSummary({ hasCollision: false, with: [] });
    setStatus("Loading room model...");

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(sceneColor("sceneBackground"));

    const camera = new THREE.PerspectiveCamera(50, width / height, 0.01, 1000);
    camera.position.set(5, 4, 8);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.shadowMap.enabled = true;
    root.appendChild(renderer.domElement);

    const labelRenderer = new CSS2DRenderer();
    labelRenderer.setSize(width, height);
    labelRenderer.domElement.className = "test-three-label-layer";
    root.appendChild(labelRenderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;

    scene.add(
      new THREE.HemisphereLight(
        sceneColor("hemisphereSky"),
        sceneColor("hemisphereGround"),
        2.2,
      ),
    );
    const sun = new THREE.DirectionalLight(sceneColor("sun"), 1.7);
    sun.position.set(5, 8, 6);
    sun.castShadow = true;
    scene.add(sun);

    const worldGroup = new THREE.Group();
    worldGroup.name = "RoomEditScene";
    scene.add(worldGroup);

    const furnitureLayer = new THREE.Group();
    furnitureLayer.name = "EditableFurnitureLayer";
    const referenceLayer = new THREE.Group();
    referenceLayer.name = "DoorWindowReferenceLayer";
    const selectionLayer = new THREE.Group();
    selectionLayer.name = "SelectionControlLayer";
    worldGroup.add(furnitureLayer, referenceLayer, selectionLayer);

    const controlPickTargets = [];
    const floorPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    const floorHitPoint = new THREE.Vector3();
    const upAxis = new THREE.Vector3(0, 1, 0);
    const selectionRing = new THREE.Mesh(
      new THREE.RingGeometry(0.92, 1, 72),
      new THREE.MeshBasicMaterial({
        color: sceneColor("selectedEdge"),
        opacity: 0.82,
        transparent: true,
        depthTest: false,
        depthWrite: false,
        side: THREE.DoubleSide,
      }),
    );
    const selectionHandle = new THREE.Mesh(
      new THREE.SphereGeometry(1, 20, 12),
      new THREE.MeshBasicMaterial({
        color: sceneColor("selectionHandle"),
        opacity: 0.95,
        transparent: true,
        depthTest: false,
        depthWrite: false,
      }),
    );
    const selectionLine = new THREE.Line(
      new THREE.BufferGeometry(),
      new THREE.LineBasicMaterial({
        color: sceneColor("selectedEdge"),
        opacity: 0.75,
        transparent: true,
        depthTest: false,
      }),
    );
    let activeInteraction = null;

    selectionRing.rotation.x = -Math.PI / 2;
    selectionRing.renderOrder = 30;
    selectionHandle.renderOrder = 31;
    selectionLine.renderOrder = 30;
    selectionRing.visible = false;
    selectionHandle.visible = false;
    selectionLine.visible = false;
    selectionHandle.userData.controlType = "rotate";
    selectionLayer.add(selectionRing, selectionLine, selectionHandle);
    controlPickTargets.push(selectionHandle);

    function setPointerRay(event) {
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(mouse, camera);
    }

    function intersectObjectFloor(event, object, target) {
      floorPlane.set(upAxis, -object.position.y);
      setPointerRay(event);
      return raycaster.ray.intersectPlane(floorPlane, target);
    }

    function angleOnFloor(center, point) {
      return Math.atan2(point.x - center.x, point.z - center.z);
    }

    function capturePointer(pointerId) {
      try {
        renderer.domElement.setPointerCapture(pointerId);
      } catch (_error) {
        // Pointer capture can fail if the pointer was already released.
      }
    }

    function releasePointer(pointerId) {
      try {
        renderer.domElement.releasePointerCapture(pointerId);
      } catch (_error) {
        // Pointer capture can fail if the pointer was already released.
      }
    }

    function stopSceneEvent(event) {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation?.();
    }

    function updateSelectionOverlay(object = selectedObjectRef.current) {
      if (!object) {
        selectionRing.visible = false;
        selectionHandle.visible = false;
        selectionLine.visible = false;
        selectionHandle.userData.editableRoot = null;
        return;
      }

      const bounds = new THREE.Box3().setFromObject(object);
      if (bounds.isEmpty()) {
        selectionRing.visible = false;
        selectionHandle.visible = false;
        selectionLine.visible = false;
        selectionHandle.userData.editableRoot = null;
        return;
      }

      const size = bounds.getSize(new THREE.Vector3());
      const radius = Math.max(0.35, Math.max(size.x, size.z) * 0.58 + 0.18);
      const baseY = bounds.min.y + 0.025;

      selectionRing.position.set(object.position.x, baseY, object.position.z);
      selectionRing.scale.set(radius, radius, 1);
      selectionRing.visible = true;

      if (!canTransformObject(object)) {
        selectionHandle.visible = false;
        selectionLine.visible = false;
        selectionHandle.userData.editableRoot = null;
        return;
      }

      const forward = new THREE.Vector3(0, 0, 1).applyQuaternion(
        object.quaternion,
      );
      forward.y = 0;
      if (forward.lengthSq() <= 1e-8) {
        forward.set(0, 0, 1);
      } else {
        forward.normalize();
      }

      const handleDistance = radius + Math.max(0.14, radius * 0.12);
      const handleSize = Math.max(0.12, radius * 0.12);
      const handlePosition = new THREE.Vector3(
        object.position.x + forward.x * handleDistance,
        baseY + handleSize * 1.2,
        object.position.z + forward.z * handleDistance,
      );

      selectionHandle.position.copy(handlePosition);
      selectionHandle.scale.setScalar(handleSize);
      selectionHandle.visible = true;
      selectionHandle.userData.editableRoot = object;

      selectionLine.geometry.setFromPoints([
        selectionRing.position.clone(),
        handlePosition.clone(),
      ]);
      selectionLine.visible = true;
    }

    function beginMoveInteraction(event, object) {
      if (!intersectObjectFloor(event, object, floorHitPoint)) return false;

      activeInteraction = {
        type: "move",
        pointerId: event.pointerId,
        object,
        offset: object.position.clone().sub(floorHitPoint),
        y: object.position.y,
      };
      controls.enabled = false;
      renderer.domElement.style.cursor = "grabbing";
      capturePointer(event.pointerId);
      return true;
    }

    function beginRotateInteraction(event, object) {
      if (!intersectObjectFloor(event, object, floorHitPoint)) return false;

      activeInteraction = {
        type: "rotate",
        pointerId: event.pointerId,
        object,
        center: object.position.clone(),
        startAngle: angleOnFloor(object.position, floorHitPoint),
        startQuaternion: object.quaternion.clone(),
      };
      controls.enabled = false;
      renderer.domElement.style.cursor = "grabbing";
      capturePointer(event.pointerId);
      return true;
    }

    function updateActiveInteraction(event) {
      if (
        !activeInteraction ||
        event.pointerId !== activeInteraction.pointerId
      ) {
        return;
      }

      const { object } = activeInteraction;
      if (!object || !intersectObjectFloor(event, object, floorHitPoint))
        return;

      if (activeInteraction.type === "move") {
        object.position.copy(floorHitPoint).add(activeInteraction.offset);
        object.position.y = activeInteraction.y;
      } else if (activeInteraction.type === "rotate") {
        const angle = angleOnFloor(activeInteraction.center, floorHitPoint);
        const delta = angle - activeInteraction.startAngle;
        object.position.copy(activeInteraction.center);
        object.quaternion
          .copy(activeInteraction.startQuaternion)
          .premultiply(new THREE.Quaternion().setFromAxisAngle(upAxis, delta));
      }

      object.updateWorldMatrix(true, false);
      clampObjectToWallBoundary(object, wallColliders);
      syncSceneState(object);
    }

    function endActiveInteraction(event) {
      if (
        !activeInteraction ||
        event.pointerId !== activeInteraction.pointerId
      ) {
        return;
      }

      const { object } = activeInteraction;
      activeInteraction = null;
      controls.enabled = true;
      renderer.domElement.style.cursor = "default";
      releasePointer(event.pointerId);
      syncSceneState(object);
    }

    function syncSceneState(selectedObject = selectedObjectRef.current) {
      const collisions = refreshCollisionState(
        editableRoots,
        selectedObject,
        wallColliders,
      );
      const exportedItems = editableRoots.map(objectToEditableJson);

      setEditedItems(exportedItems);
      setSelectedItem(
        selectedObject ? objectToEditableJson(selectedObject) : null,
      );
      setCollisionSummary({
        hasCollision: collisions.length > 0,
        with: collisions,
      });
      updateSelectionOverlay(selectedObject);
    }

    function selectObject(object) {
      selectedObjectRef.current = object;

      if (!object) {
        setSelectedItem(null);
        syncSceneState(null);
        return;
      }

      syncSceneState(object);
    }

    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();

    function handlePointerDown(event) {
      if (event.button !== 0) return;

      setPointerRay(event);

      const controlHits = raycaster
        .intersectObjects(controlPickTargets, false)
        .filter(
          (hit) => hit.object.visible && hit.object.userData.editableRoot,
        );
      if (controlHits.length) {
        const object = controlHits[0].object.userData.editableRoot;
        selectObject(object);
        if (beginRotateInteraction(event, object)) {
          stopSceneEvent(event);
        }
        return;
      }

      const hits = raycaster.intersectObjects(pickTargets, true);
      if (!hits.length) {
        selectObject(null);
        return;
      }

      const object = hits[0].object.userData.editableRoot;
      selectObject(object);

      if (canTransformObject(object)) {
        beginMoveInteraction(event, object);
      }
      stopSceneEvent(event);
    }

    function handlePointerMove(event) {
      if (
        !activeInteraction ||
        event.pointerId !== activeInteraction.pointerId
      ) {
        return;
      }

      updateActiveInteraction(event);
      stopSceneEvent(event);
    }

    function handlePointerEnd(event) {
      if (
        !activeInteraction ||
        event.pointerId !== activeInteraction.pointerId
      ) {
        return;
      }

      endActiveInteraction(event);
      stopSceneEvent(event);
    }

    renderer.domElement.addEventListener(
      "pointerdown",
      handlePointerDown,
      true,
    );
    renderer.domElement.addEventListener(
      "pointermove",
      handlePointerMove,
      true,
    );
    renderer.domElement.addEventListener("pointerup", handlePointerEnd, true);
    renderer.domElement.addEventListener(
      "pointercancel",
      handlePointerEnd,
      true,
    );

    // 변수 추가
    Promise.all([
      loadUsdRoomModel(getRoomModelUrl()),
      fetchJson(getRoomMetadataUrl(), "room metadata"),
    ])
      .then(([model, metadata]) =>
        Promise.all([
          model,
          loadModelTemplates(modelCategoriesFromMetadata(metadata)),
          metadata,
        ]),
      )
      // 변수 추가
      .then(
        ([
          model,
          modelTemplates,
          metadata,
        ]) => {
          if (!isMounted) {
            if (model) disposeScene(model);
            modelTemplates.forEach((template) =>
              disposeScene(template.gltf.scene),
            );
            return;
          }

          const jsonRoomModel = createRoomModelFromJson(metadata._spatiumRoom);
          const roomModel = jsonRoomModel || model;
          if (!roomModel) {
            throw new Error(
              "Room model is missing. Provide USDZ or JSON room meshes.",
            );
          }
          if (jsonRoomModel && model) {
            disposeScene(model);
          }

          sourceMetadataRef.current = metadata;
          roomModelRef.current = roomModel;
          roomModel.name = jsonRoomModel ? "JsonRoomLayer" : "RoomLayer";
          prepareRoomModel(roomModel);
          worldGroup.add(roomModel);
          wallColliders.push(...createWallColliders(roomModel));
          if (wallConfigBoolean("showColliderDebug")) {
            referenceLayer.add(createWallColliderVisuals(wallColliders));
          }

          // 카테고리 구별 로직 추가
          (metadata.objects || []).forEach((item, index) => {
            const modelTemplate = findModelTemplate(
              modelTemplates,
              item.category,
            );
            const furniture = modelTemplate
              ? createEditableFurnitureModel(
                  modelTemplate.gltf.scene,
                  item,
                  index,
                )
              : createEditableFurniture(item, index);

            furnitureLayer.add(furniture.root);
            editableRoots.push(furniture.root);
            pickTargets.push(...furniture.pickTargets);
          });

          const doorTemplate = requireModelTemplate(modelTemplates, "door");
          (metadata.doors || []).forEach((item, index) => {
            const door = createDoorModel(doorTemplate.gltf.scene, item, index);
            referenceLayer.add(door.root);
            pickTargets.push(...door.pickTargets);
          });

          const windowTemplate = (metadata.windows || []).length
            ? requireModelTemplate(modelTemplates, "window")
            : null;
          (metadata.windows || []).forEach((item, index) => {
            const windowModel = createWindowModel(
              windowTemplate.gltf.scene,
              item,
              index,
            );
            referenceLayer.add(windowModel.root);
            pickTargets.push(...windowModel.pickTargets);
          });

          initializeWallConstraints(editableRoots, wallColliders);

          if (editableRoots[0]) selectObject(editableRoots[0]);
          if (!editableRoots.length) syncSceneState(null);
          frameObject(camera, controls, worldGroup);
          setStatus("");
        },
      )
      .catch((caughtError) => {
        if (!isMounted) return;
        setStatus("");
        setError(
          caughtError instanceof Error
            ? caughtError.message
            : String(caughtError),
        );
      });

    function animate() {
      frameId = requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
      labelRenderer.render(scene, camera);
    }
    animate();

    function resize() {
      const nextWidth = root.clientWidth || window.innerWidth;
      const nextHeight = root.clientHeight || window.innerHeight;
      camera.aspect = nextWidth / nextHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(nextWidth, nextHeight);
      labelRenderer.setSize(nextWidth, nextHeight);
    }

    window.addEventListener("resize", resize);
    syncSelectedRef.current = () => syncSceneState(selectedObjectRef.current);

    return () => {
      isMounted = false;
      cancelAnimationFrame(frameId);
      window.removeEventListener("resize", resize);
      renderer.domElement.removeEventListener(
        "pointerdown",
        handlePointerDown,
        true,
      );
      renderer.domElement.removeEventListener(
        "pointermove",
        handlePointerMove,
        true,
      );
      renderer.domElement.removeEventListener(
        "pointerup",
        handlePointerEnd,
        true,
      );
      renderer.domElement.removeEventListener(
        "pointercancel",
        handlePointerEnd,
        true,
      );
      selectedObjectRef.current = null;
      syncSelectedRef.current = null;
      sourceMetadataRef.current = null;
      roomModelRef.current = null;
      setCollisionSummary({ hasCollision: false, with: [] });
      controls.dispose();
      disposeScene(scene);
      renderer.dispose();
      root.replaceChildren();
    };
  }, [isSceneConfigReady]);

  return (
    <div className="test-three-page">
      <div ref={containerRef} className="test-three-viewport" />
      <aside className="test-three-panel">
        <h1 className="test-three-title">Furniture Edit</h1>
        <div className="test-three-actions">
          <button
            type="button"
            onClick={resetSelectedObject}
            disabled={!canResetSelected}
            className="test-three-button test-three-button--secondary"
          >
            Reset
          </button>
          <button
            type="button"
            onClick={saveEditedSceneJson}
            disabled={!canSaveJson}
            className="test-three-button test-three-button--primary"
          >
            Save JSON
          </button>
        </div>
        <p className="test-three-count">
          {editedItems.length} editable objects
        </p>
        <div
          className={`test-three-collision ${
            collisionSummary.hasCollision
              ? "test-three-collision--active"
              : "test-three-collision--clear"
          }`}
        >
          {collisionSummary.hasCollision
            ? `Collision: ${collisionSummary.with.join(", ")}`
            : "Collision: clear"}
        </div>
        <pre className="test-three-json-preview">
          {JSON.stringify(selectedItem || editedItems[0] || {}, null, 2)}
        </pre>
      </aside>
      {status && <div className="test-three-status">{status}</div>}
      {error && <pre className="test-three-error">{error}</pre>}
    </div>
  );
}
