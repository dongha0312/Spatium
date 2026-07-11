import * as THREE from "three";
import {
  applyReferencePreviewVisibility,
  referenceVisibilityState,
  updateReferenceDebugLabel,
} from "./referenceVisibility";

// 벽 mesh 전체(면 단위 분리 불가한 경우의 fallback)를 통째로 반투명하게 만든다.
// 원래 opacity/transparent 값은 첫 호출 시 material.userData에 저장해두고 복원에 사용한다.
function applyWallPreviewOpacity(object, hidden) {
  // 매 프레임 호출되므로, hidden 상태가 지난번과 같으면 traverse/material 갱신을 건너뛴다.
  if (object.userData.spatiumWallPreviewHidden === hidden) return;
  object.userData.spatiumWallPreviewHidden = hidden;

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

// 아래 재사용 벡터들은 삼각형-벽 소속 계산(콜라이더당 1회, O(전체 삼각형))과 매 프레임
// 카메라 방향 판정에서 호출마다 Vector3를 새로 만들지 않기 위한 모듈 스코프 임시 객체다.
const previewAxisThickness = new THREE.Vector3();
const previewAxisHeight = new THREE.Vector3();
const previewAxisLength = new THREE.Vector3();
const previewRelative = new THREE.Vector3();
const previewVertex = new THREE.Vector3();
const previewCenterSum = new THREE.Vector3();
const previewTriangleCenter = new THREE.Vector3();
const previewToCamera = new THREE.Vector3();

// 삼각형 중심점이 이 벽 콜라이더의 OBB 범위 안에 있는지 판정한다 — "이 삼각형이 카메라를
// 가리고 있는 벽 face인가"를 판단하는 데 쓰인다.
function wallPreviewContainsTriangle(wall, triangleCenter) {
  if (!triangleCenter) return false;

  wall.obb.rotation.extractBasis(
    previewAxisThickness,
    previewAxisHeight,
    previewAxisLength,
  );

  previewRelative.copy(triangleCenter).sub(wall.obb.center);
  const thicknessDistance = Math.abs(
    previewRelative.dot(previewAxisThickness),
  );
  const heightDistance = Math.abs(previewRelative.dot(previewAxisHeight));
  const lengthDistance = Math.abs(previewRelative.dot(previewAxisLength));

  return (
    thicknessDistance <= wall.obb.halfSize.x &&
    heightDistance <= wall.obb.halfSize.y &&
    lengthDistance <= wall.obb.halfSize.z
  );
}

// 벽 mesh를 "face 단위로 material을 바꿀 수 있는 상태"로 준비한다. 원래 material마다
// 투명 버전을 하나씩 복제해서 뒤에 추가해두고, 삼각형별 원본 material index와 삼각형
// 중심(월드 좌표, 방 mesh는 정적이므로 1회 계산)을 미리 만들어둔다. 이후에는 숨길 삼각형
// 조합이 바뀔 때만 geometry.groups를 "연속 구간 병합" 방식으로 재구성한다 — 예전처럼
// 삼각형 1개당 group 1개(= draw call 1개)를 상시 유지하지 않는다.
// 한 번 준비되면 userData.spatiumWallFacePreview에 캐시해서 재사용한다.
function ensureWallFacePreviewState(object) {
  const geometry = object.geometry;
  const position = geometry?.attributes?.position;
  if (!position) return null;

  if (object.userData.spatiumWallFacePreview) {
    return object.userData.spatiumWallFacePreview;
  }

  const originals = materialArray(object.material).filter(Boolean);
  if (!originals.length) return null;

  const index = geometry.index;
  const drawCount = index ? index.count : position.count;
  const triangleCount = Math.floor(drawCount / 3);
  const originalGroups = geometry.groups.length
    ? geometry.groups.map((group) => ({ ...group }))
    : [{ start: 0, count: drawCount, materialIndex: 0 }];

  // 삼각형별 원본 material index (group 재구성 시 참조).
  const triangleMaterialIndex = new Uint16Array(triangleCount);
  originalGroups.forEach((group) => {
    const startTriangle = Math.max(0, Math.floor(group.start / 3));
    const endTriangle = Math.min(
      triangleCount,
      Math.ceil((group.start + group.count) / 3),
    );
    for (let triangle = startTriangle; triangle < endTriangle; triangle += 1) {
      triangleMaterialIndex[triangle] = group.materialIndex || 0;
    }
  });

  // 방 mesh는 월드에서 움직이지 않으므로 삼각형 중심을 한 번만 계산해둔다.
  object.updateWorldMatrix(true, false);
  const triangleCentersWorld = new Float32Array(triangleCount * 3);
  for (let triangle = 0; triangle < triangleCount; triangle += 1) {
    previewCenterSum.set(0, 0, 0);
    for (let offset = 0; offset < 3; offset += 1) {
      const vertexIndex = index
        ? index.getX(triangle * 3 + offset)
        : triangle * 3 + offset;
      previewVertex.fromBufferAttribute(position, vertexIndex);
      previewCenterSum.add(previewVertex);
    }
    previewCenterSum.multiplyScalar(1 / 3).applyMatrix4(object.matrixWorld);
    triangleCentersWorld[triangle * 3] = previewCenterSum.x;
    triangleCentersWorld[triangle * 3 + 1] = previewCenterSum.y;
    triangleCentersWorld[triangle * 3 + 2] = previewCenterSum.z;
  }

  const transparentMaterials = originals.map((material) => {
    const transparentMaterial = material.clone();

    transparentMaterial.transparent = true;
    transparentMaterial.opacity = 0.04;
    transparentMaterial.depthWrite = false;
    transparentMaterial.needsUpdate = true;
    return transparentMaterial;
  });

  const state = {
    originalMaterialCount: originals.length,
    triangleCount,
    triangleMaterialIndex,
    triangleCentersWorld,
    hiddenMask: new Uint8Array(triangleCount),
    appliedKey: "",
  };

  object.material = [...originals, ...transparentMaterials];
  object.userData.spatiumWallFacePreview = state;
  // material이 배열이 되면 group 범위만 렌더링되므로, 전체를 덮는 초기 group을
  // (병합된 형태로) 반드시 만들어줘야 한다 — 원본 geometry에 group이 없던 경우 필수.
  rebuildWallFaceGroups(object, state);
  return state;
}

// 이 벽 콜라이더가 숨겨질 때 함께 투명해져야 하는 삼각형 목록(콜라이더 OBB 안에 중심이
// 있는 삼각형들). geometry와 콜라이더 OBB가 모두 정적이므로 콜라이더당 1회만 계산해서
// 콜라이더 객체에 캐시한다 — 콜라이더가 재생성되면(벽으로 메우기 등) 자동으로 다시 계산된다.
function hiddenTrianglesForWall(wall, state) {
  if (!wall.spatiumHiddenTriangles) {
    const triangles = [];
    for (let triangle = 0; triangle < state.triangleCount; triangle += 1) {
      previewTriangleCenter.set(
        state.triangleCentersWorld[triangle * 3],
        state.triangleCentersWorld[triangle * 3 + 1],
        state.triangleCentersWorld[triangle * 3 + 2],
      );
      if (wallPreviewContainsTriangle(wall, previewTriangleCenter)) {
        triangles.push(triangle);
      }
    }
    wall.spatiumHiddenTriangles = triangles;
  }

  return wall.spatiumHiddenTriangles;
}

// hiddenMask(삼각형별 숨김 여부)에 따라 geometry.groups를 다시 만든다. 연속된 삼각형 중
// (원본 material, 숨김 여부)가 같은 구간을 group 하나로 병합하므로, group 수(= draw call
// 수)가 삼각형 수가 아니라 "구간 수" 수준으로 유지된다.
function rebuildWallFaceGroups(object, state) {
  const geometry = object.geometry;
  geometry.clearGroups();

  let runStartTriangle = 0;
  let runMaterialIndex = -1;

  for (let triangle = 0; triangle < state.triangleCount; triangle += 1) {
    const materialIndex =
      state.triangleMaterialIndex[triangle] +
      (state.hiddenMask[triangle] ? state.originalMaterialCount : 0);

    if (materialIndex === runMaterialIndex) continue;

    if (runMaterialIndex >= 0) {
      geometry.addGroup(
        runStartTriangle * 3,
        (triangle - runStartTriangle) * 3,
        runMaterialIndex,
      );
    }
    runStartTriangle = triangle;
    runMaterialIndex = materialIndex;
  }

  if (runMaterialIndex >= 0) {
    geometry.addGroup(
      runStartTriangle * 3,
      (state.triangleCount - runStartTriangle) * 3,
      runMaterialIndex,
    );
  }
}

// 벽 mesh 하나에 대해, 이번 프레임에 숨겨야 할 face 콜라이더 목록(hiddenWalls)을 반영한다.
// 숨길 조합이 직전 적용 상태(appliedKey)와 같으면 아무것도 하지 않는다 — group 재구성은
// 카메라가 벽 경계를 넘나드는 순간에만 일어난다.
function applyWallFacePreviewForObject(wallObject, hiddenWalls) {
  // 한 번도 숨긴 적 없는 mesh는 원본 그대로 두고 준비 작업도 미룬다.
  if (!hiddenWalls.length && !wallObject.userData.spatiumWallFacePreview) {
    return;
  }

  const state = ensureWallFacePreviewState(wallObject);
  if (!state) {
    applyWallPreviewOpacity(wallObject, hiddenWalls.length > 0);
    return;
  }

  const key = hiddenWalls
    .map((wall) => `${wall.triangleStart}:${wall.triangleCount}`)
    .sort()
    .join("|");
  if (state.appliedKey === key) return;
  state.appliedKey = key;

  state.hiddenMask.fill(0);
  hiddenWalls.forEach((wall) => {
    const triangles = hiddenTrianglesForWall(wall, state);
    for (let i = 0; i < triangles.length; i += 1) {
      state.hiddenMask[triangles[i]] = 1;
    }
  });

  rebuildWallFaceGroups(wallObject, state);
}

// 카메라가 벽의 roomFacingNormal 반대편(바깥쪽)에서 안쪽을 바라보고 있으면 true.
// 즉 이 벽이 "카메라와 방 내부 사이를 가로막고 있다"는 뜻.
function isWallHiddenFromCamera(wall, camera) {
  if (!wall.roomFacingNormal) return false;

  previewToCamera.copy(camera.position).sub(wall.obb.center).normalize();
  return previewToCamera.dot(wall.roomFacingNormal) < -0.2;
}

// 렌더 루프에서 "카메라가 움직였거나 벽/문/창문 구성이 바뀐 프레임"에만 호출된다
// (useRoomSceneEditor의 animate 참고). 카메라 시야를 가리는 벽 face와 문/창문을
// 반투명하게 만들어서 방 내부가 보이게 한다. 실제 geometry group 재구성은 이 안에서도
// 한 번 더 걸러져서, 숨길 face 조합이 직전과 달라진 mesh에 대해서만 일어난다.
export function updateViewFacingWalls(
  wallColliders,
  camera,
  referenceRoots = [],
) {
  // mesh object별로 이번 프레임에 숨겨야 할 face 콜라이더들을 모은다. 숨길 게 없는
  // 벽 mesh도 빈 배열로 등록해야 이전 프레임에 숨겼던 face가 복원된다.
  const faceWallsByObject = new Map();
  const fallbackVisibilityByObject = new Map();

  wallColliders.forEach((wall) => {
    const hidden = isWallHiddenFromCamera(wall, camera);

    if (
      Number.isFinite(wall.triangleStart) &&
      Number.isFinite(wall.triangleCount)
    ) {
      let hiddenWalls = faceWallsByObject.get(wall.object);
      if (!hiddenWalls) {
        hiddenWalls = [];
        faceWallsByObject.set(wall.object, hiddenWalls);
      }
      if (hidden) hiddenWalls.push(wall);
      return;
    }

    const currentHidden = fallbackVisibilityByObject.get(wall.object) || false;
    fallbackVisibilityByObject.set(wall.object, currentHidden || hidden);
  });

  faceWallsByObject.forEach((hiddenWalls, wallObject) => {
    applyWallFacePreviewForObject(wallObject, hiddenWalls);
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
