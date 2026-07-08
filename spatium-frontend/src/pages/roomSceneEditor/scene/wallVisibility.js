import * as THREE from "three";
import {
  applyReferencePreviewVisibility,
  referenceVisibilityState,
  updateReferenceDebugLabel,
} from "./referenceVisibility";

function applyWallPreviewOpacity(object, hidden) {
  object.traverse?.((child) => {
    const materials = Array.isArray(child.material)
      ? child.material
      : [child.material];

    materials.forEach((material) => {
      if (!material) return;
      if (!material.userData.spatiumOriginalWallState) {
        material.userData.spatiumOriginalWallState = {
          opacity: material.opacity,
          transparent: material.transparent,
          depthWrite: material.depthWrite,
        };
      }

      const original = material.userData.spatiumOriginalWallState;
      material.transparent = hidden || original.transparent;
      material.opacity = hidden ? 0.04 : original.opacity;
      material.depthWrite = hidden ? false : original.depthWrite;
      material.needsUpdate = true;
    });
  });
}

function materialArray(material) {
  return Array.isArray(material) ? material : [material];
}

function findMaterialIndexForTriangle(geometry, triangleStart) {
  const group = geometry.groups.find(
    ({ start, count }) =>
      triangleStart >= start && triangleStart < start + count,
  );

  return group?.materialIndex || 0;
}

function triangleCenterWorld(object, triangleStart) {
  const geometry = object.geometry;
  const position = geometry?.attributes?.position;
  if (!position) return null;

  const index = geometry.index;
  const center = new THREE.Vector3();
  const vertex = new THREE.Vector3();

  for (let offset = 0; offset < 3; offset += 1) {
    const vertexIndex = index
      ? index.getX(triangleStart + offset)
      : triangleStart + offset;

    vertex.fromBufferAttribute(position, vertexIndex);
    center.add(vertex);
  }

  return center.multiplyScalar(1 / 3).applyMatrix4(object.matrixWorld);
}

function wallPreviewContainsTriangle(wall, triangleCenter) {
  if (!triangleCenter) return false;

  const axes = {
    thickness: new THREE.Vector3(),
    height: new THREE.Vector3(),
    length: new THREE.Vector3(),
  };
  wall.obb.rotation.extractBasis(axes.thickness, axes.height, axes.length);

  const relative = triangleCenter.clone().sub(wall.obb.center);
  const thicknessDistance = Math.abs(relative.dot(axes.thickness));
  const heightDistance = Math.abs(relative.dot(axes.height));
  const lengthDistance = Math.abs(relative.dot(axes.length));
  const thicknessPadding = 0;
  const spanPadding = 0;

  return (
    thicknessDistance <= wall.obb.halfSize.x + thicknessPadding &&
    heightDistance <= wall.obb.halfSize.y + spanPadding &&
    lengthDistance <= wall.obb.halfSize.z + spanPadding
  );
}

function ensureWallFacePreviewState(object) {
  const geometry = object.geometry;
  if (!geometry) return null;

  if (object.userData.spatiumWallFacePreview) {
    return object.userData.spatiumWallFacePreview;
  }

  const originals = materialArray(object.material).filter(Boolean);
  if (!originals.length) return null;

  const originalGroups = geometry.groups.length
    ? geometry.groups.map((group) => ({ ...group }))
    : [
        {
          start: 0,
          count: geometry.index
            ? geometry.index.count
            : geometry.attributes.position.count,
          materialIndex: 0,
        },
      ];
  const transparentMaterials = originals.map((material) => {
    const transparentMaterial = material.clone();

    transparentMaterial.transparent = true;
    transparentMaterial.opacity = 0.04;
    transparentMaterial.depthWrite = false;
    transparentMaterial.needsUpdate = true;
    return transparentMaterial;
  });

  const drawCount = geometry.index
    ? geometry.index.count
    : geometry.attributes.position.count;

  geometry.clearGroups();
  for (let triangleStart = 0; triangleStart < drawCount; triangleStart += 3) {
    const originalMaterialIndex = findMaterialIndexForTriangle(
      { groups: originalGroups },
      triangleStart,
    );

    geometry.addGroup(triangleStart, 3, originalMaterialIndex);
  }

  const state = {
    originalMaterialCount: originals.length,
    originalGroups,
  };

  object.material = [...originals, ...transparentMaterials];
  object.userData.spatiumWallFacePreview = state;
  return state;
}

function resetWallFacePreview(object) {
  const state = object.userData.spatiumWallFacePreview;
  if (!state || !object.geometry) return;

  object.geometry.groups.forEach((group) => {
    if (group.materialIndex >= state.originalMaterialCount) {
      group.materialIndex -= state.originalMaterialCount;
    }
  });
}

function applyWallFacePreview(wall, hidden) {
  if (
    !Number.isFinite(wall.triangleStart) ||
    !Number.isFinite(wall.triangleCount)
  ) {
    applyWallPreviewOpacity(wall.object, hidden);
    return;
  }

  const state = ensureWallFacePreviewState(wall.object);
  if (!state) {
    applyWallPreviewOpacity(wall.object, hidden);
    return;
  }

  const geometry = wall.object.geometry;
  const groups = hidden
    ? geometry.groups.filter((group) =>
        wallPreviewContainsTriangle(
          wall,
          triangleCenterWorld(wall.object, group.start),
        ),
      )
    : geometry.groups.filter(
        ({ start, count }) =>
          start === wall.triangleStart && count === wall.triangleCount,
      );

  groups.forEach((group) => {
    const originalMaterialIndex =
      group.materialIndex >= state.originalMaterialCount
        ? group.materialIndex - state.originalMaterialCount
        : group.materialIndex;

    group.materialIndex = hidden
      ? originalMaterialIndex + state.originalMaterialCount
      : originalMaterialIndex;
  });
}

function isWallHiddenFromCamera(wall, camera) {
  const toCamera = camera.position.clone().sub(wall.obb.center).normalize();
  return wall.roomFacingNormal && toCamera.dot(wall.roomFacingNormal) < -0.2;
}

export function updateViewFacingWalls(
  wallColliders,
  camera,
  referenceRoots = [],
) {
  const wallObjects = new Set(wallColliders.map((wall) => wall.object));
  const fallbackVisibilityByObject = new Map();

  wallObjects.forEach((wallObject) => {
    resetWallFacePreview(wallObject);
  });

  wallColliders.forEach((wall) => {
    const hidden = isWallHiddenFromCamera(wall, camera);

    if (
      Number.isFinite(wall.triangleStart) &&
      Number.isFinite(wall.triangleCount)
    ) {
      applyWallFacePreview(wall, hidden);
      return;
    }

    const currentHidden = fallbackVisibilityByObject.get(wall.object) || false;
    fallbackVisibilityByObject.set(wall.object, currentHidden || hidden);
  });

  fallbackVisibilityByObject.forEach((hidden, wallObject) => {
    applyWallPreviewOpacity(wallObject, hidden);
  });

  referenceRoots.forEach((reference) => {
    const state = referenceVisibilityState(reference, camera);
    updateReferenceDebugLabel(reference, state);
    applyReferencePreviewVisibility(reference, state.hidden);
  });
}

export function applyRoomWallColor(wallColliders, color) {
  if (!color) return;

  const nextColor = new THREE.Color(color);
  const wallObjects = new Set(wallColliders.map((wall) => wall.object));

  wallObjects.forEach((wallObject) => {
    wallObject.traverse?.((child) => {
      const materials = Array.isArray(child.material)
        ? child.material
        : [child.material];

      materials.forEach((material) => {
        if (!material?.color) return;

        material.color.copy(nextColor);
        if (material.userData.spatiumOriginalWallState) {
          material.userData.spatiumOriginalWallState.color = nextColor.clone();
        }
        material.needsUpdate = true;
      });
    });
  });
}
