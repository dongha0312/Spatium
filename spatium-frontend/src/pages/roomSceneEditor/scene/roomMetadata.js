import * as THREE from "three";
import {
  SCENE_CONFIG_URL,
  getModelUrls,
  sceneColor,
} from "./sceneConfig";
import {
  cloneJsonValue,
  columnsFromMatrix,
  matrixFromColumns,
} from "./threeUtils";
import {
  isUsdFloorMesh,
  isUsdReplacedMesh,
  isUsdWallMesh,
} from "./wallColliders";

// 가구/문/창문 오브젝트 하나를 저장 가능한 JSON(위치/회전/치수/충돌 정보)으로 변환한다.
// 선택 정보 패널 표시와 metadata 저장(createReplayableMetadataJson) 양쪽에서 공통으로 쓰인다.
export function objectToEditableJson(object) {
  object.updateMatrix();
  object.updateWorldMatrix(true, true);
  const item = object.userData.roomItem || {};
  const sourceType = object.userData.sourceType || "object";
  const sourceIndex = object.userData.sourceIndex;
  const collisions = object.userData.collisions || [];
  const localObbSize = object.userData.localObb?.halfSize
    ?.clone()
    .multiplyScalar(2);
  const bounds = localObbSize ? null : new THREE.Box3().setFromObject(object);
  const fallbackSize = localObbSize || (bounds.isEmpty()
    ? new THREE.Vector3(
        item.dimensions?.x || 0,
        item.dimensions?.y || 0,
        item.dimensions?.z || 0,
      )
    : bounds.getSize(new THREE.Vector3()));
  const stableSize = new THREE.Vector3(
    Number(item.dimensions?.x) || fallbackSize.x,
    Number(item.dimensions?.y) || fallbackSize.y,
    Number(item.dimensions?.z) || fallbackSize.z,
  );
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
    catalogId: item.catalogId,
    name: item.name,
    category: item.category || object.userData.category || "object",
    path: item.path || item.modelUrl,
    modelUrl: item.modelUrl,
    dimensions: {
      x: Number(stableSize.x.toFixed(4)),
      y: Number(stableSize.y.toFixed(4)),
      z: Number(stableSize.z.toFixed(4)),
    },
    dimensionsCm: {
      width: Math.round(stableSize.x * 100),
      height: Math.round(stableSize.y * 100),
      depth: Math.round(stableSize.z * 100),
    },
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

export function roundedNumber(value, digits = 6) {
  return Number(Number(value).toFixed(digits));
}

export function roundedArray(values, digits = 6) {
  return Array.from(values, (value) => roundedNumber(value, digits));
}

// THREE material을 저장 가능한 JSON으로 요약한다 (_spatiumRoom 저장/복원에 사용).
export function materialToRoomJson(material) {
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

// 방 mesh 하나(벽/바닥/기타)를 geometry(position/normal/uv/index)와 material까지 통째로
// JSON으로 직렬화한다. 원본 USD 모델 없이도 다시 그릴 수 있도록 필요한 모든 정보를 담는다.
export function serializeRoomMesh(object) {
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

// 방 모델 전체(벽/바닥/기타 mesh)를 순회하며 직렬화한다. 삭제된 것으로 표시된 mesh
// (isUsdReplacedMesh, 원본 스캔의 문/창문 등)는 제외한다. 결과가 metadata._spatiumRoom에 저장된다.
export function serializeRoomModelToJson(roomModel, generatedFrom = null) {
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
    generatedFrom,
    walls,
    floors,
    meshes,
  };
}

// _spatiumRoom JSON에서 walls/floors/meshes를 하나의 배열로 합친다 (순서: 벽 -> 바닥 -> 기타).
export function roomMeshesFromJson(roomJson) {
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

// serializeRoomModelToJson()의 역변환. 저장된 _spatiumRoom JSON으로부터 Three.js
// BufferGeometry/Mesh들을 복원해서 방 모델 그룹을 다시 만든다. 원본 USD 모델이 없어도
// 이 결과만으로 방을 다시 그릴 수 있다.
export function createRoomModelFromJson(roomJson) {
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

// 원본 metadata + 현재 편집 상태(editedItems, roomModel)를 합쳐서, 저장 시 서버로 보낼
// 최종 metadata JSON을 만든다. objects/doors/windows는 현재 씬 기준으로 통째로 교체하고,
// _spatiumRoom(방 mesh 자체)도 다시 직렬화해서 넣는다 — 이렇게 저장된 JSON은 원본 USD
// 모델 없이도 다시 열어서 편집을 이어갈 수 있다("replayable").
export function createReplayableMetadataJson(
  metadata,
  editedItems,
  roomModel,
  floorColor = null,
) {
  const nextMetadata = cloneJsonValue(metadata) || {};
  const originalObjects = nextMetadata.objects || [];
  const originalDoors = nextMetadata.doors || [];
  const originalWindows = nextMetadata.windows || [];
  const originalOpenings = nextMetadata.openings || [];
  const objectEdits = editedItems.filter(
    (item) => item.sourceType === "object",
  );
  const doorEdits = editedItems.filter((item) => item.sourceType === "door");
  const windowEdits = editedItems.filter(
    (item) => item.sourceType === "window",
  );
  // 개구부(문/창문을 "개구부로 삭제"해서 남은 빈 구멍 마커)도 저장해둬야 다음에
  // 방을 다시 열었을 때 그 자리에 문/창문을 채워 넣을 수 있다.
  const openingEdits = editedItems.filter(
    (item) => item.sourceType === "opening",
  );

  const applyReferenceEdit = (edit, originalItems) => {
    const original = originalItems[edit.index] || {};
    return {
      ...original,
      catalogId: edit.catalogId,
      name: edit.name,
      category: edit.category,
      path: edit.path,
      modelUrl: edit.modelUrl,
      dimensions: edit.dimensions,
      transform: edit.transform,
    };
  };

  nextMetadata.objects = objectEdits.map((edit) => {
    const original = originalObjects[edit.index] || {};
    return {
      ...original,
      catalogId: edit.catalogId,
      name: edit.name,
      category: edit.category,
      path: edit.path,
      modelUrl: edit.modelUrl,
      dimensions: edit.dimensions,
      transform: edit.transform,
    };
  });

  // editedItems는 현재 씬의 전체 상태를 반영하므로(문/창문을 모두 지운 경우 포함),
  // 비어 있다고 originalDoors/originalWindows로 되돌리면 삭제가 저장에서 사라진다.
  nextMetadata.doors = doorEdits.map((edit) =>
    applyReferenceEdit(edit, originalDoors),
  );
  nextMetadata.windows = windowEdits.map((edit) =>
    applyReferenceEdit(edit, originalWindows),
  );
  nextMetadata.openings = openingEdits.map((edit) =>
    applyReferenceEdit(edit, originalOpenings),
  );
  nextMetadata._spatiumRoom =
    serializeRoomModelToJson(
      roomModel,
      nextMetadata._spatiumRoom?.generatedFrom || "api:room-scene",
    ) ||
    nextMetadata._spatiumRoom ||
    null;
  nextMetadata._spatiumFloorColor = floorColor || null;
  nextMetadata._spatiumExport = {
    version: 1,
    exportedAt: new Date().toISOString(),
    source: {
      sceneConfigUrl: SCENE_CONFIG_URL,
      modelUrls: getModelUrls(),
    },
    editedItems,
  };

  return nextMetadata;
}
