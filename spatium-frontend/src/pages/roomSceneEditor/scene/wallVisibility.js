import * as THREE from "three";
import {
  applyReferencePreviewVisibility,
  referenceVisibilityState,
  updateReferenceDebugLabel,
} from "./referenceVisibility";

// 벽 mesh 전체(면 단위 분리 불가한 경우의 fallback)를 통째로 반투명하게 만든다.
// 원래 opacity/transparent 값은 첫 호출 시 material.userData에 저장해두고 복원에 사용한다.
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

// 특정 삼각형(triangleStart)이 geometry.groups 중 어느 그룹(=어느 material)에 속하는지 찾는다.
function findMaterialIndexForTriangle(geometry, triangleStart) {
  const group = geometry.groups.find(
    ({ start, count }) =>
      triangleStart >= start && triangleStart < start + count,
  );

  return group?.materialIndex || 0;
}

// 삼각형 하나(3개 정점)의 월드 좌표 중심점을 계산한다.
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

// 삼각형 중심점이 이 벽 콜라이더의 OBB 범위 안에 있는지 판정한다 — "이 삼각형이 카메라를
// 가리고 있는 벽 face인가"를 판단하는 데 쓰인다.
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

// 벽 mesh를 "삼각형 단위로 material을 바꿀 수 있는 상태"로 준비한다. 원래 material마다
// 투명 버전을 하나씩 복제해서 뒤에 추가해두고, geometry를 삼각형 단위 group으로 쪼갠다.
// 이렇게 해두면 이후 특정 삼각형의 materialIndex만 바꿔서 그 face만 투명하게 만들 수 있다.
// 한 번 준비되면 userData.spatiumWallFacePreview에 캐시해서 재사용한다.
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

// 매 프레임 시작 시, 지난 프레임에 투명 처리했던 group들을 전부 원래 material로 되돌린다
// (이번 프레임에 다시 필요한 곳만 새로 투명하게 칠하기 위한 초기화).
function resetWallFacePreview(object) {
  const state = object.userData.spatiumWallFacePreview;
  if (!state || !object.geometry) return;

  object.geometry.groups.forEach((group) => {
    if (group.materialIndex >= state.originalMaterialCount) {
      group.materialIndex -= state.originalMaterialCount;
    }
  });
}

// 벽 콜라이더 하나에 대해, 카메라를 가리면(hidden) 해당 face의 삼각형들만 투명 material로
// 바꾼다. face 단위 정보(triangleStart/Count)가 없는 벽은 mesh 전체를 흐리는 방식으로
// fallback한다.
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

// 카메라가 벽의 roomFacingNormal 반대편(바깥쪽)에서 안쪽을 바라보고 있으면 true.
// 즉 이 벽이 "카메라와 방 내부 사이를 가로막고 있다"는 뜻.
function isWallHiddenFromCamera(wall, camera) {
  const toCamera = camera.position.clone().sub(wall.obb.center).normalize();
  return wall.roomFacingNormal && toCamera.dot(wall.roomFacingNormal) < -0.2;
}

// 매 프레임(애니메이션 루프) 호출된다. 카메라 시야를 가리는 벽 face와 문/창문을 반투명하게
// 만들어서 방 내부가 보이게 한다. 모든 벽 콜라이더/참조 오브젝트를 순회하며 처리한다.
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

// 모든 벽 material의 색상을 지정한 색으로 바꾼다. color가 없으면(null) 아무것도 하지 않는다
// — 즉 사용자가 벽 색을 따로 지정하지 않으면 스캔 당시의 원래 색/텍스처가 유지된다.
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
