import * as THREE from "three";
import { OBB } from "three/examples/jsm/math/OBB.js";
import { categoryColor, referenceFallbackThickness, sceneColor } from "./sceneConfig";
import { createLabel, decomposeRoomTransform } from "./threeUtils";

export function createEditableFurniture(item, index) {
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
