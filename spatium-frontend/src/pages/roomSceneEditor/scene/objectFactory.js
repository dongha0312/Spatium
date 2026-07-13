import * as THREE from "three";
import { OBB } from "three/examples/jsm/math/OBB.js";
import {
  categoryColor,
  referenceFallbackThickness,
  sceneColor,
} from "./sceneConfig";
import { decomposeRoomTransform } from "./threeUtils";
import { measureWallThicknessAtPosition } from "./wallColliders";

const REFERENCE_THICKNESS_MARGIN = 0.01;
const REFERENCE_THICKNESS_MIN = 0.02;
const WALL_INFILL_PADDING = 0.06;
const WALL_INFILL_MIN_THICKNESS = 0.04;

// wallColliders 배열(콜라이더 여러 개가 같은 mesh를 가리킬 수 있음)에서 중복 없는
// 원본 벽 mesh 목록만 뽑는다 (실측 두께 계산은 콜라이더가 아니라 mesh 자체가 필요하다).
function wallMeshesFromColliders(wallColliders) {
  return [
    ...new Set(
      (wallColliders || []).map((collider) => collider.object).filter(Boolean),
    ),
  ];
}

// 문/창문이 실제 벽보다 두꺼워서 앞뒤로 튀어나오지 않도록, 속한 벽의 실측 두께에
// 맞춰 두께를 줄이고 위치를 그 벽의 두께 방향 중심으로 재정렬한다.
// 근처에 벽을 찾지 못하면(open scene 등) 원래 값을 그대로 반환한다.
function fitReferenceToWallThickness(targetSize, position, wallColliders) {
  const wallMeshes = wallMeshesFromColliders(wallColliders);
  const measurement = measureWallThicknessAtPosition(position, wallMeshes);
  if (!measurement) {
    return { targetSize, position };
  }

  const clampedThickness = Math.max(
    REFERENCE_THICKNESS_MIN,
    measurement.thickness - REFERENCE_THICKNESS_MARGIN,
  );
  const nextTargetSize = targetSize.clone();
  nextTargetSize.z = Math.min(targetSize.z, clampedThickness);

  const currentProjection = position.dot(measurement.normal);
  const nextPosition = position
    .clone()
    .addScaledVector(
      measurement.normal,
      measurement.centerProjection - currentProjection,
    );

  return { targetSize: nextTargetSize, position: nextPosition };
}

// 원점에 중심을 둔 OBB를 만든다 (fallback box 가구 등, 모델 없이 크기만 아는 경우).
function createCenteredLocalObb(size) {
  return new OBB(new THREE.Vector3(0, 0, 0), size.clone().multiplyScalar(0.5));
}

// 실제 GLB 모델의 geometry bounds로부터 local OBB를 만든다. bounds가 비어있거나
// 이상하면(0 이하 크기) createCenteredLocalObb로 fallback한다.
function createLocalObbFromBounds(bounds, fallbackSize) {
  if (!bounds || bounds.isEmpty()) {
    return createCenteredLocalObb(fallbackSize);
  }

  const size = bounds.getSize(new THREE.Vector3());
  if (size.x <= 0 || size.y <= 0 || size.z <= 0) {
    return createCenteredLocalObb(fallbackSize);
  }

  return new OBB(
    bounds.getCenter(new THREE.Vector3()),
    size.multiplyScalar(0.5),
  );
}

// localObb 크기의 박스 외곽선(EdgesGeometry)을 만든다. 기본은 안 보이게(visible=false)
// 해두고, 선택/충돌 시에만 setFurnitureVisualState()가 보이게 켠다.
function createCollisionBoxLine(localObb, opacity = 0.55) {
  const size = localObb.halfSize.clone().multiplyScalar(2);
  const boxGeometry = new THREE.BoxGeometry(size.x, size.y, size.z);
  const edgeGeometry = new THREE.EdgesGeometry(boxGeometry);
  const edge = new THREE.LineSegments(
    edgeGeometry,
    new THREE.LineBasicMaterial({
      color: sceneColor("defaultEdge"),
      transparent: true,
      opacity,
    }),
  );
  const rotation = new THREE.Matrix4().setFromMatrix3(localObb.rotation);

  boxGeometry.dispose();
  edge.name = "collision-box-line";
  edge.position.copy(localObb.center);
  edge.quaternion.setFromRotationMatrix(rotation);
  edge.visible = false;
  return edge;
}

// 화면에는 안 그려지지만(opacity 0) 레이캐스트 피킹은 되는 material.
// GLB 모델 자체의 복잡한 mesh 대신, 이 material을 쓴 박스(hitBox)로 클릭 판정을 단순화한다.
function createPickOnlyMaterial(color) {
  return new THREE.MeshBasicMaterial({
    color,
    opacity: 0,
    transparent: true,
    depthWrite: false,
    colorWrite: false,
  });
}

// localObb 크기의 투명 박스 mesh. pickTargets에 등록되어 실제 클릭/선택 판정에 쓰인다.
function createCollisionHitBox(localObb, color) {
  const size = localObb.halfSize.clone().multiplyScalar(2);
  const geometry = new THREE.BoxGeometry(size.x, size.y, size.z);
  const mesh = new THREE.Mesh(geometry, createPickOnlyMaterial(color));

  mesh.position.copy(localObb.center);
  return mesh;
}

// 모델의 모든 material을 복제한다. 같은 GLB 템플릿을 여러 인스턴스가 공유하므로,
// 개별 인스턴스의 색상/투명도(충돌 표시, 유리 투명화 등)를 바꾸기 전에 반드시 복제해야
// 다른 인스턴스에 영향이 안 간다.
function cloneRenderableMaterials(object) {
  object.traverse((child) => {
    if (!child.material) return;

    child.material = Array.isArray(child.material)
      ? child.material.map((material) => material.clone())
      : child.material.clone();
  });
}

// GLB 템플릿이 없는 가구를 위한 fallback — 단색 반투명 박스로 가구를 표현한다.
export function createEditableFurniture(item, index) {
  const dimensions = item.dimensions || {};
  const category = item.category || "object";
  const color = categoryColor(category);
  const width = Math.max(dimensions.x || 0.1, 0.04);
  const height = Math.max(dimensions.y || 0.1, 0.04);
  const depth = Math.max(dimensions.z || 0.1, 0.04);
  const localObb = createCenteredLocalObb(
    new THREE.Vector3(width, height, depth),
  );
  const geometry = new THREE.BoxGeometry(width, height, depth);
  const material = new THREE.MeshStandardMaterial({
    color,
    opacity: 0.72,
    transparent: true,
    roughness: 0.72,
  });
  const mesh = new THREE.Mesh(geometry, material);
  const edge = createCollisionBoxLine(localObb, 0.5);
  const root = new THREE.Group();
  const transform = decomposeRoomTransform(item);

  root.name = `${category}-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);
  root.userData = {
    editable: true,
    roomItem: item,
    sourceType: "object",
    sourceIndex: index,
    localObb,
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

  root.add(mesh, edge);
  return { root, pickTargets: [mesh] };
}

// 오브젝트(및 자식들)의 모든 정점을 순회해서 정확한 월드 좌표 bounding box를 구한다.
// THREE.Box3.setFromObject보다 느리지만, 스킨/모프 없는 정적 모델에서 더 정확하다.
export function getBaseGeometryBounds(object) {
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

// 모델을 목표 크기(targetSize, 미터)에 맞춰 스케일하고 중심을 원점으로 이동시킨다.
// 여러 번 호출해도(리사이즈 등) 매번 "현재 bounds -> 목표 크기" 비율로 다시 스케일하므로 결과가 수렴한다.
export function fitModelToTargetSize(model, targetSize) {
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

// 일부 GLB 템플릿(문/창문/가구 공통)에 섞여 있는, 원래 모델과 무관한 부산물
// (예: UI 킷 잔여물의 검은/흰 판, 화면/스크린 mesh)을 이름 패턴으로 찾아서 제거한다.
function removeModelArtifacts(model) {
  const artifactNamePatterns = [/^Blender Bros Sci-Fi UI Pack/i, /^Solid 25$/i];
  const artifactMaterialPatterns = [
    /^\.?Blender Bros Sci-Fi UI Pack/i,
    /^Black plastic PL$/i,
    /^Monitor Screen$/i,
  ];
  const artifacts = [];

  model.traverse((object) => {
    const materials = Array.isArray(object.material)
      ? object.material
      : [object.material];
    if (
      object !== model &&
      (artifactNamePatterns.some((pattern) =>
        pattern.test(object.name || ""),
      ) ||
        materials.some((material) =>
          artifactMaterialPatterns.some((pattern) =>
            pattern.test(material?.name || ""),
          ),
        ))
    ) {
      artifacts.push(object);
    }
  });

  artifacts.forEach((object) => {
    object.parent?.remove(object);
  });
}

const GLASS_MATERIAL_NAME_PATTERN = /glass/i;
const GLASS_OPACITY = 0.1;

// 문/창문 GLB의 "유리" 재질은 alphaMode가 OPAQUE로 export되어 있어서(glTF 원본 데이터
// 자체가 불투명) three.js가 그대로 불투명하게 렌더링한다. 재질 이름으로 유리를 찾아서
// transparent/opacity를 강제로 설정해준다. cloneRenderableMaterials() 이후에 호출해야
// 같은 GLB를 쓰는 다른 인스턴스의 재질에 영향을 주지 않는다.
function applyGlassTransparency(model) {
  model.traverse((object) => {
    if (!object.isMesh) return;

    const materials = Array.isArray(object.material)
      ? object.material
      : [object.material];

    materials.forEach((material) => {
      if (!material || !GLASS_MATERIAL_NAME_PATTERN.test(material.name || "")) {
        return;
      }

      material.transparent = true;
      material.opacity = GLASS_OPACITY;
      material.depthWrite = false;
      material.needsUpdate = true;
    });
  });
}

// GLB 템플릿이 있는 일반 가구를 만든다. 템플릿을 clone하고 목표 크기로 fit한 뒤,
// 그 결과 bounds로 충돌용 localObb/hitBox/edge를 만든다.
export function createEditableFurnitureModel(modelTemplate, item, index) {
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

  root.name = `${category}-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);

  removeModelArtifacts(model);
  model.traverse((object) => {
    if (object.isMesh) {
      object.castShadow = true;
      object.receiveShadow = true;
      object.userData.editableRoot = root;
    }
  });

  fitModelToTargetSize(model, targetSize);

  const localObb = createLocalObbFromBounds(
    getBaseGeometryBounds(model),
    targetSize,
  );
  const hitBox = createCollisionHitBox(localObb, categoryColor(category));
  const edge = createCollisionBoxLine(localObb);

  root.userData = {
    editable: true,
    roomItem: item,
    sourceType: "object",
    sourceIndex: index,
    localObb,
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

  hitBox.userData.editableRoot = root;
  edge.userData.editableRoot = root;

  root.add(model, hitBox, edge);
  return { root, pickTargets: [hitBox] };
}

// 문/창문을 "개구부로 삭제"했을 때 그 자리에 남기는 마커를 만든다. 벽에 뚫린 구멍
// 자체는 이미 존재하므로 모델 없이 클릭 가능한 hitBox와 항상 보이는 테두리만 만든다.
// 나중에 카탈로그에서 문/창문을 선택해 이 마커를 "교체"하면 그 자리에 다시 채워진다.
export function createOpeningMarker(item, index) {
  const dimensions = item.dimensions || {};
  const targetSize = new THREE.Vector3(
    Math.max(dimensions.x || 0.1, 0.04),
    Math.max(dimensions.y || 0.1, 0.04),
    Math.max(dimensions.z || 0.04, 0.04),
  );
  const localObb = createCenteredLocalObb(targetSize);
  const root = new THREE.Group();
  const transform = decomposeRoomTransform(item);
  const hitBox = createCollisionHitBox(localObb, sceneColor("openingReference"));
  const edge = createCollisionBoxLine(localObb, 0.55);

  root.name = `opening-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);

  edge.material.color.set(sceneColor("openingReference"));
  edge.visible = true;

  root.userData = {
    editable: false,
    category: "opening",
    roomItem: { ...item, category: "opening" },
    sourceType: "opening",
    sourceIndex: index,
    localObb,
    edgeLine: edge,
    baseEdgeColor: new THREE.Color(sceneColor("openingReference")),
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

  hitBox.userData.editableRoot = root;
  edge.userData.editableRoot = root;

  root.add(hitBox, edge);
  return { root, pickTargets: [hitBox] };
}

// 문 reference 오브젝트를 만든다 (editable:false, sourceType:"door"). 두께/위치는
// fitReferenceToWallThickness로 속한 벽에 맞춰 보정하고, 유리 재질은 투명 처리한다.
export function createDoorModel(doorTemplate, item, index, wallColliders = []) {
  const doorItem = { ...item, category: "door" };
  const dimensions = item.dimensions || {};
  const fallbackThickness = referenceFallbackThickness("door");
  const rawTargetSize = new THREE.Vector3(
    Math.max(dimensions.x || 0.1, 0.04),
    Math.max(dimensions.y || 0.1, 0.04),
    Math.max(dimensions.z || fallbackThickness, fallbackThickness),
  );
  const root = new THREE.Group();
  const model = doorTemplate.clone(true);
  const transform = decomposeRoomTransform(item);
  const { targetSize, position } = fitReferenceToWallThickness(
    rawTargetSize,
    transform.position,
    wallColliders,
  );

  root.name = `door-${index + 1}`;
  root.position.copy(position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);

  removeModelArtifacts(model);
  cloneRenderableMaterials(model);
  applyGlassTransparency(model);
  model.traverse((object) => {
    if (object.isMesh) {
      object.castShadow = true;
      object.receiveShadow = true;
      object.userData.editableRoot = root;
    }
  });

  fitModelToTargetSize(model, targetSize);

  const localObb = createLocalObbFromBounds(
    getBaseGeometryBounds(model),
    targetSize,
  );
  const hitBox = createCollisionHitBox(localObb, sceneColor("doorReference"));
  const edge = createCollisionBoxLine(localObb);

  root.userData = {
    editable: false,
    category: "door",
    roomItem: doorItem,
    sourceType: "door",
    sourceIndex: index,
    localObb,
    edgeLine: edge,
    baseEdgeColor: new THREE.Color(sceneColor("defaultEdge")),
    selectedEdgeColor: new THREE.Color(sceneColor("selectedEdge")),
    collisionColor: new THREE.Color(sceneColor("collision")),
    collisions: [],
    initialPosition: position.clone(),
    initialQuaternion: transform.quaternion.clone(),
    initialScale: transform.scale.clone(),
    lastValidPosition: position.clone(),
    lastValidQuaternion: transform.quaternion.clone(),
    lastValidScale: transform.scale.clone(),
  };

  hitBox.userData.editableRoot = root;
  edge.userData.editableRoot = root;

  root.add(model, hitBox, edge);
  return { root, pickTargets: [hitBox] };
}

// 창문 reference 오브젝트를 만든다. createDoorModel과 구조가 동일하고 category만 다르다.
export function createWindowModel(
  windowTemplate,
  item,
  index,
  wallColliders = [],
) {
  const windowItem = { ...item, category: "window" };
  const dimensions = item.dimensions || {};
  const fallbackThickness = referenceFallbackThickness("window");
  const rawTargetSize = new THREE.Vector3(
    Math.max(dimensions.x || 0.1, 0.04),
    Math.max(dimensions.y || 0.1, 0.04),
    Math.max(dimensions.z || fallbackThickness, fallbackThickness),
  );
  const root = new THREE.Group();
  const model = windowTemplate.clone(true);
  const transform = decomposeRoomTransform(item);
  const { targetSize, position } = fitReferenceToWallThickness(
    rawTargetSize,
    transform.position,
    wallColliders,
  );

  root.name = `window-${index + 1}`;
  root.position.copy(position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);

  removeModelArtifacts(model);
  cloneRenderableMaterials(model);
  applyGlassTransparency(model);
  model.traverse((object) => {
    if (object.isMesh) {
      object.castShadow = true;
      object.receiveShadow = true;
      object.userData.editableRoot = root;
    }
  });

  fitModelToTargetSize(model, targetSize);

  const localObb = createLocalObbFromBounds(
    getBaseGeometryBounds(model),
    targetSize,
  );
  const hitBox = createCollisionHitBox(localObb, sceneColor("windowReference"));
  const edge = createCollisionBoxLine(localObb);

  root.userData = {
    editable: false,
    category: "window",
    roomItem: windowItem,
    sourceType: "window",
    sourceIndex: index,
    localObb,
    edgeLine: edge,
    baseEdgeColor: new THREE.Color(sceneColor("defaultEdge")),
    selectedEdgeColor: new THREE.Color(sceneColor("selectedEdge")),
    collisionColor: new THREE.Color(sceneColor("collision")),
    collisions: [],
    initialPosition: position.clone(),
    initialQuaternion: transform.quaternion.clone(),
    initialScale: transform.scale.clone(),
    lastValidPosition: position.clone(),
    lastValidQuaternion: transform.quaternion.clone(),
    lastValidScale: transform.scale.clone(),
  };

  hitBox.userData.editableRoot = root;
  edge.userData.editableRoot = root;

  root.add(model, hitBox, edge);
  return { root, pickTargets: [hitBox] };
}

// 매칭된 벽 mesh의 material을 그대로 복제해서 쓴다 — 색상뿐 아니라 roughness/metalness,
// (있다면) 텍스처까지 같이 맞춰져서 메운 자리가 원래 벽과 자연스럽게 이어져 보인다.
// 매칭된 벽을 못 찾은 경우에만 기본 색상으로 fallback한다.
function materialForWallInfill(wallObject) {
  const source = Array.isArray(wallObject?.material)
    ? wallObject.material[0]
    : wallObject?.material;

  if (source?.clone) {
    const cloned = source.clone();
    cloned.userData = {};
    cloned.transparent = false;
    cloned.opacity = 1;
    cloned.needsUpdate = true;
    return cloned;
  }

  return new THREE.MeshStandardMaterial({
    color: sceneColor("roomMaterialDefault"),
    roughness: 0.9,
  });
}

// 문/창문을 "벽으로 메우기"로 삭제할 때 그 자리를 채우는 mesh를 만든다. reference의
// 실제 크기(localObb)와 속한 벽의 실측 두께/중심을 기준으로 박스를 만들고,
// userData.isUsdWallMesh를 직접 표시해서 이후 벽 콜라이더 생성과 저장(_spatiumRoom)에서
// 일반 벽 mesh와 동일하게 취급되게 한다.
// 이름은 "Door"/"Window"로 시작하지 않아야 한다 — isUsdReplacedMesh()가 그 패턴을
// 원본 스캔 문/창문 mesh로 오인해 저장에서 제외시키기 때문이다.
export function createWallInfillMesh(referenceRoot, wallColliders, index = 0) {
  const halfSize = referenceRoot.userData.localObb?.halfSize;
  const width = (halfSize ? halfSize.x * 2 : 0.9) + WALL_INFILL_PADDING;
  const height = (halfSize ? halfSize.y * 2 : 2.0) + WALL_INFILL_PADDING;

  const wallMeshes = wallMeshesFromColliders(wallColliders);
  const measurement = measureWallThicknessAtPosition(
    referenceRoot.position,
    wallMeshes,
  );
  const thickness = Math.max(
    measurement?.thickness || (halfSize ? halfSize.z * 2 : 0),
    WALL_INFILL_MIN_THICKNESS,
  );

  const geometry = new THREE.BoxGeometry(width, height, thickness);
  const material = materialForWallInfill(measurement?.object);
  const mesh = new THREE.Mesh(geometry, material);

  mesh.name = `Infill_${referenceRoot.userData.sourceType || "opening"}_${index}`;
  mesh.position.copy(referenceRoot.position);
  mesh.quaternion.copy(referenceRoot.quaternion);

  if (measurement) {
    const currentProjection = mesh.position.dot(measurement.normal);
    mesh.position.addScaledVector(
      measurement.normal,
      measurement.centerProjection - currentProjection,
    );
  }

  mesh.updateMatrixWorld(true);
  mesh.castShadow = false;
  mesh.receiveShadow = true;
  mesh.userData.isUsdWallMesh = true;

  return mesh;
}
