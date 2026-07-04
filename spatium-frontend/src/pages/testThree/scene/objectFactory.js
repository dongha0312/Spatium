import * as THREE from "three";
import { OBB } from "three/examples/jsm/math/OBB.js";
import { categoryColor, referenceFallbackThickness, sceneColor } from "./sceneConfig";
import { decomposeRoomTransform } from "./threeUtils";

function createCenteredLocalObb(size) {
  return new OBB(
    new THREE.Vector3(0, 0, 0),
    size.clone().multiplyScalar(0.5),
  );
}

function createLocalObbFromBounds(bounds, fallbackSize) {
  if (!bounds || bounds.isEmpty()) {
    return createCenteredLocalObb(fallbackSize);
  }

  const size = bounds.getSize(new THREE.Vector3());
  if (size.x <= 0 || size.y <= 0 || size.z <= 0) {
    return createCenteredLocalObb(fallbackSize);
  }

  return new OBB(bounds.getCenter(new THREE.Vector3()), size.multiplyScalar(0.5));
}

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

function createPickOnlyMaterial(color) {
  return new THREE.MeshBasicMaterial({
    color,
    opacity: 0,
    transparent: true,
    depthWrite: false,
    colorWrite: false,
  });
}

function createCollisionHitBox(localObb, color) {
  const size = localObb.halfSize.clone().multiplyScalar(2);
  const geometry = new THREE.BoxGeometry(size.x, size.y, size.z);
  const mesh = new THREE.Mesh(geometry, createPickOnlyMaterial(color));

  mesh.position.copy(localObb.center);
  return mesh;
}

function cloneRenderableMaterials(object) {
  object.traverse((child) => {
    if (!child.material) return;

    child.material = Array.isArray(child.material)
      ? child.material.map((material) => material.clone())
      : child.material.clone();
  });
}

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

function removeReferenceModelArtifacts(model) {
  const artifactNamePatterns = [
    /^Blender Bros Sci-Fi UI Pack/i,
    /^Solid 25$/i,
  ];
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
      (artifactNamePatterns.some((pattern) => pattern.test(object.name || "")) ||
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

export function createDoorModel(doorTemplate, item, index) {
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

  root.name = `door-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);

  removeReferenceModelArtifacts(model);
  cloneRenderableMaterials(model);
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

export function createWindowModel(windowTemplate, item, index) {
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

  root.name = `window-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);

  removeReferenceModelArtifacts(model);
  cloneRenderableMaterials(model);
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
