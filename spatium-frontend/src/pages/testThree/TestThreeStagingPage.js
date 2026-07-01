import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { TransformControls } from "three/examples/jsm/controls/TransformControls.js";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { USDLoader } from "three/examples/jsm/loaders/USDLoader.js";
import { OBB } from "three/examples/jsm/math/OBB.js";
import {
  CSS2DObject,
  CSS2DRenderer,
} from "three/examples/jsm/renderers/CSS2DRenderer.js";

const ROOM_MODEL_URL =
  "/testdata/room-scan.usdz";
const ROOM_METADATA_URL =
  "/testdata/ai-edit-request.json";
const DOOR_MODEL_URL = "/testdata/3d_models/door.glb";
const CHAIR_MODEL_URL = "/testdata/3d_models/chair2.glb";
const TABLE_MODEL_URL = "/testdata/3d_models/table2.glb";
const STORAGE_MODEL_URL = "/testdata/3d_models/storage.glb";
const DOOR_FALLBACK_THICKNESS = 0.08;

// 색깔 요소 JSON으로 빼서 외부에서 참조할 수 있게 변경
const CATEGORY_COLORS = {
  chair: "#5f8f74",
  table: "#c08b57",
  storage: "#8fa4b8",
  sofa: "#7f9fb0",
  refrigerator: "#b7c7cf",
  oven: "#c98282",
  object: "#9aa0a6",
};
const COLLISION_COLOR = "#d94b4b";
const SELECTED_EDGE_COLOR = "#ffcf5a";
const DEFAULT_EDGE_COLOR = "#1f2724";
const WALL_COLLISION_EPSILON = 0;
const WALL_CLAMP_ITERATIONS = 14;
const WALL_SWEEP_STEP = 0.03;
const WALL_SWEEP_ROTATION_STEP = THREE.MathUtils.degToRad(2);
const WALL_SWEEP_MAX_STEPS = 240;

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
	if (value && typeof value === "object" && typeof value.dispose === "function") {
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
  return CATEGORY_COLORS[category] || CATEGORY_COLORS.object;
}

function decomposeRoomTransform(item) {
  const position = new THREE.Vector3();
  const quaternion = new THREE.Quaternion();
  const scale = new THREE.Vector3();
  matrixFromColumns(item.transform.columns).decompose(position, quaternion, scale);
  return { position, quaternion, scale };
}

function objectToEditableJson(object) {
  object.updateMatrix();
  const item = object.userData.roomItem;
  const collisions = object.userData.collisions || [];
  const matrix = new THREE.Matrix4().compose(
	object.position,
	object.quaternion,
	object.scale
  );
  const rotation = new THREE.Euler().setFromQuaternion(object.quaternion);

  return {
	index: object.userData.sourceIndex,
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
		column.map((value) => Number(value.toFixed(6)))
	  ),
	},
	collision: {
	  hasCollision: collisions.length > 0,
	  with: collisions,
	},
  };
}

function editableObjectLabel(object) {
  const item = object.userData.roomItem;
  return `${item.category || object.userData.category || "object"} ${
	object.userData.sourceIndex + 1
  }`;
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
  const category = object?.userData.roomItem?.category || object?.userData.category;
  return Boolean(object?.userData.editable && category !== "door");
}

function hasWallCollision(object, wallColliders) {
  if (!shouldConstrainToWalls(object) || !wallColliders.length) return false;

  const objectObb = worldObbForObject(object);
  return wallColliders.some((wall) =>
    objectObb.intersectsOBB(wall.obb, WALL_COLLISION_EPSILON)
  );
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

function clampObjectToWallBoundary(object, wallColliders) {
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
    WALL_SWEEP_MAX_STEPS,
    Math.max(
      1,
      Math.ceil(distance / WALL_SWEEP_STEP),
      Math.ceil(angle / WALL_SWEEP_ROTATION_STEP)
    )
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

  const best = {
    position: valid.position.clone(),
    quaternion: valid.quaternion.clone(),
    scale: valid.scale.clone(),
  };

  for (let i = 0; i < WALL_CLAMP_ITERATIONS; i += 1) {
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
	  hasCollision ? object.userData.collisionColor : object.userData.baseColor
	);
	mesh.material.opacity = hasCollision ? 0.88 : 0.72;
  }

  if (edge?.material) {
	edge.material.color.copy(
	  hasCollision
		? object.userData.collisionColor
		: isSelected
		  ? object.userData.selectedEdgeColor
		  : object.userData.baseEdgeColor
	);
	edge.material.opacity = hasCollision || isSelected ? 0.95 : 0.5;
  }
}

function refreshCollisionState(editableObjects, selectedObject) {
  editableObjects.forEach((object) => {
	object.userData.collisions = [];
  });

  const obbs = editableObjects.map((object) => ({
	object,
	obb: worldObbForObject(object),
  }));

  for (let i = 0; i < obbs.length; i += 1) {
	for (let j = i + 1; j < obbs.length; j += 1) {
	  if (!obbs[i].obb.intersectsOBB(obbs[j].obb, 0.0001)) continue;

	  obbs[i].object.userData.collisions.push(editableObjectLabel(obbs[j].object));
	  obbs[j].object.userData.collisions.push(editableObjectLabel(obbs[i].object));
	}
  }

  editableObjects.forEach((object) => setFurnitureVisualState(object, selectedObject));
  return selectedObject?.userData.collisions || [];
}

function applyTransformMode(transformControls, mode) {
  if (!transformControls) return;

  transformControls.setMode(mode);
  transformControls.setSpace(mode === "rotate" ? "local" : "world");
  transformControls.setTranslationSnap(0.05);
  transformControls.setRotationSnap(THREE.MathUtils.degToRad(5));

  if (mode === "translate") {
	transformControls.showX = true;
	transformControls.showY = false;
	transformControls.showZ = true;
	transformControls.showXY = false;
	transformControls.showYZ = false;
	transformControls.showXZ = true;
	transformControls.showXYZE = false;
	return;
  }

  transformControls.showX = false;
  transformControls.showY = true;
  transformControls.showZ = false;
  transformControls.showXY = false;
  transformControls.showYZ = false;
  transformControls.showXZ = false;
  transformControls.showXYZE = false;
}

function createEditableFurniture(item, index) {
  const dimensions = item.dimensions || {};
  const category = item.category || "object";
  const color = categoryColor(category);
  const width = Math.max(dimensions.x || 0.1, 0.04);
  const height = Math.max(dimensions.y || 0.1, 0.04);
  const depth = Math.max(dimensions.z || 0.1, 0.04);
  const geometry = new THREE.BoxGeometry(
	width,
	height,
	depth
  );
  const material = new THREE.MeshStandardMaterial({
	color,
	opacity: 0.72,
	transparent: true,
	roughness: 0.72,
  });
  const mesh = new THREE.Mesh(geometry, material);
  const edge = new THREE.LineSegments(
	new THREE.EdgesGeometry(geometry),
	new THREE.LineBasicMaterial({ color: 0x1f2724, transparent: true, opacity: 0.5 })
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
	sourceIndex: index,
	localObb: new OBB(
	  new THREE.Vector3(0, 0, 0),
	  new THREE.Vector3(width / 2, height / 2, depth / 2)
	),
	visualMesh: mesh,
	edgeLine: edge,
	baseColor: new THREE.Color(color),
	collisionColor: new THREE.Color(COLLISION_COLOR),
	baseEdgeColor: new THREE.Color(DEFAULT_EDGE_COLOR),
	selectedEdgeColor: new THREE.Color(SELECTED_EDGE_COLOR),
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

function createReferenceBox(item, category, color) {
  const dimensions = item.dimensions || {};
  const geometry = new THREE.BoxGeometry(
	Math.max(dimensions.x || 0.1, 0.04),
	Math.max(dimensions.y || 0.1, 0.04),
	Math.max(dimensions.z || 0.05, 0.04)
  );
  const line = new THREE.LineSegments(
	new THREE.EdgesGeometry(geometry),
	new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.45 })
  );
  const label = createLabel(category, "reference-label");

  line.applyMatrix4(matrixFromColumns(item.transform.columns));
  label.position.copy(
	line.position.clone().add(new THREE.Vector3(0, (dimensions.y || 0.1) / 2 + 0.08, 0))
  );

  return [line, label];
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
    size.z > 0 ? targetSize.z / size.z : 1
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
    Math.max(dimensions.z || 0.1, 0.04)
  );
  const root = new THREE.Group();
  const model = modelTemplate.clone(true);
  const transform = decomposeRoomTransform(item);
  const label = createLabel(`${category} ${index + 1}`);
  const hitGeometry = new THREE.BoxGeometry(targetSize.x, targetSize.y, targetSize.z);
  const hitBox = new THREE.Mesh(
    hitGeometry,
    new THREE.MeshBasicMaterial({
      color: categoryColor(category),
      opacity: 0.001,
      transparent: true,
      depthWrite: false,
    })
  );
  const edge = new THREE.LineSegments(
    new THREE.EdgesGeometry(hitGeometry),
    new THREE.LineBasicMaterial({
      color: DEFAULT_EDGE_COLOR,
      transparent: true,
      opacity: 0.55,
    })
  );

  root.name = `${category}-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);
  root.userData = {
    editable: true,
    roomItem: item,
    sourceIndex: index,
    localObb: new OBB(
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(targetSize.x / 2, targetSize.y / 2, targetSize.z / 2)
    ),
    edgeLine: edge,
    baseEdgeColor: new THREE.Color(DEFAULT_EDGE_COLOR),
    selectedEdgeColor: new THREE.Color(SELECTED_EDGE_COLOR),
    collisionColor: new THREE.Color(COLLISION_COLOR),
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
  const targetSize = new THREE.Vector3(
	Math.max(dimensions.x || 0.1, 0.04),
	Math.max(dimensions.y || 0.1, 0.04),
	Math.max(dimensions.z || DOOR_FALLBACK_THICKNESS, DOOR_FALLBACK_THICKNESS)
  );
  const root = new THREE.Group();
  const model = doorTemplate.clone(true);
  const transform = decomposeRoomTransform(item);
  const label = createLabel(`door ${index + 1}`, "reference-label");
  const hitGeometry = new THREE.BoxGeometry(targetSize.x, targetSize.y, targetSize.z);
  const hitBox = new THREE.Mesh(
	hitGeometry,
	new THREE.MeshBasicMaterial({
	  color: 0xd9903d,
	  opacity: 0.001,
	  transparent: true,
	  depthWrite: false,
	})
  );
  const edge = new THREE.LineSegments(
	new THREE.EdgesGeometry(hitGeometry),
	new THREE.LineBasicMaterial({
	  color: DEFAULT_EDGE_COLOR,
	  transparent: true,
	  opacity: 0.55,
	})
  );

  root.name = `door-${index + 1}`;
  root.position.copy(transform.position);
  root.quaternion.copy(transform.quaternion);
  root.scale.copy(transform.scale);
  root.userData = {
	editable: true,
	category: "door",
	roomItem: doorItem,
	sourceIndex: index,
	localObb: new OBB(
	  new THREE.Vector3(0, 0, 0),
	  new THREE.Vector3(targetSize.x / 2, targetSize.y / 2, targetSize.z / 2)
	),
	edgeLine: edge,
	baseEdgeColor: new THREE.Color(DEFAULT_EDGE_COLOR),
	selectedEdgeColor: new THREE.Color(SELECTED_EDGE_COLOR),
	collisionColor: new THREE.Color(COLLISION_COLOR),
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
	  /^Door/i.test(cursor.name)
	) {
	  return true;
	}
	cursor = cursor.parent;
  }
  return false;
}

function isUsdWallMesh(object) {
  if (!object.isMesh) return false;

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

function createWallColliders(roomModel) {
  const colliders = [];
  roomModel.updateWorldMatrix(true, true);

  roomModel.traverse((object) => {
    if (!isUsdWallMesh(object) || !object.geometry) return;

    object.geometry.computeBoundingBox();
    if (!object.geometry.boundingBox || object.geometry.boundingBox.isEmpty()) return;

    colliders.push({
      object,
      obb: new OBB()
        .fromBox3(object.geometry.boundingBox)
        .applyMatrix4(object.matrixWorld),
    });
  });

  return colliders;
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
  const transformControlsRef = useRef(null);
  const selectedObjectRef = useRef(null);
  const syncSelectedRef = useRef(null);
  const [mode, setMode] = useState("translate");
  const [status, setStatus] = useState("Loading room model...");
  const [error, setError] = useState("");
  const [selectedItem, setSelectedItem] = useState(null);
  const [editedItems, setEditedItems] = useState([]);
  const [collisionSummary, setCollisionSummary] = useState({
	hasCollision: false,
	with: [],
  });

  useEffect(() => {
	applyTransformMode(transformControlsRef.current, mode);
  }, [mode]);

  function updateEditedItem(object) {
	const nextItem = objectToEditableJson(object);
	setSelectedItem(nextItem);
	setEditedItems((items) =>
	  items.map((item) => (item.index === nextItem.index ? nextItem : item))
	);
  }

  function resetSelectedObject() {
	const object = selectedObjectRef.current;
	if (!object) return;

	object.position.copy(object.userData.initialPosition);
	object.quaternion.copy(object.userData.initialQuaternion);
	object.scale.copy(object.userData.initialScale);
	rememberValidTransform(object);
	if (syncSelectedRef.current) {
	  syncSelectedRef.current();
	} else {
	  updateEditedItem(object);
	}
  }

  useEffect(() => {
	if (!containerRef.current) return undefined;

	let isMounted = true;
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
	scene.background = new THREE.Color(0xf4f1ea);

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
	labelRenderer.domElement.style.position = "absolute";
	labelRenderer.domElement.style.inset = "0";
	labelRenderer.domElement.style.pointerEvents = "none";
	root.appendChild(labelRenderer.domElement);

	const controls = new OrbitControls(camera, renderer.domElement);
	controls.enableDamping = true;

	const transformControls = new TransformControls(camera, renderer.domElement);
	let isApplyingWallConstraint = false;
	transformControlsRef.current = transformControls;
	applyTransformMode(transformControls, "translate");
	scene.add(transformControls.getHelper());
	transformControls.detach();

	transformControls.addEventListener("dragging-changed", (event) => {
	  controls.enabled = !event.value;
	});
	transformControls.addEventListener("objectChange", () => {
	  if (!isApplyingWallConstraint) {
		isApplyingWallConstraint = true;
		clampObjectToWallBoundary(selectedObjectRef.current, wallColliders);
		isApplyingWallConstraint = false;
	  }
	  if (syncSelectedRef.current) syncSelectedRef.current();
	});

	scene.add(new THREE.HemisphereLight(0xffffff, 0xd8cfc0, 2.2));
	const sun = new THREE.DirectionalLight(0xffffff, 1.7);
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
	worldGroup.add(furnitureLayer, referenceLayer);

	function syncSceneState(selectedObject = selectedObjectRef.current) {
	  const collisions = refreshCollisionState(editableRoots, selectedObject);
	  const exportedItems = editableRoots.map(objectToEditableJson);

	  setEditedItems(exportedItems);
	  setSelectedItem(selectedObject ? objectToEditableJson(selectedObject) : null);
	  setCollisionSummary({
		hasCollision: collisions.length > 0,
		with: collisions,
	  });
	}

	function selectObject(object) {
	  selectedObjectRef.current = object;

	  if (!object) {
		transformControls.detach();
		setSelectedItem(null);
		syncSceneState(null);
		return;
	  }

	  transformControls.attach(object);
	  syncSceneState(object);
	}

	const raycaster = new THREE.Raycaster();
	const mouse = new THREE.Vector2();

	function handlePointerDown(event) {
	  if (transformControls.dragging || transformControls.axis) return;

	  const rect = renderer.domElement.getBoundingClientRect();
	  mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
	  mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
	  raycaster.setFromCamera(mouse, camera);

	  const hits = raycaster.intersectObjects(pickTargets, true);
	  if (!hits.length) {
		selectObject(null);
		return;
	  }

	  selectObject(hits[0].object.userData.editableRoot);
	}

	renderer.domElement.addEventListener("pointerdown", handlePointerDown);

	// 변수 추가
    Promise.all([
      new Promise((resolve, reject) => {
        new USDLoader().load(ROOM_MODEL_URL, resolve, undefined, reject);
      }),
      new Promise((resolve, reject) => {
        new GLTFLoader().load(DOOR_MODEL_URL, resolve, undefined, reject);
      }),
      new Promise((resolve, reject) => {
        new GLTFLoader().load(CHAIR_MODEL_URL, resolve, undefined, reject);
      }),
	  new Promise((resolve, reject) => {
        new GLTFLoader().load(TABLE_MODEL_URL, resolve, undefined, reject);
      }),
	  new Promise((resolve, reject) => {
        new GLTFLoader().load(STORAGE_MODEL_URL, resolve, undefined, reject);
      }),
      fetch(ROOM_METADATA_URL).then((response) => {
        if (!response.ok) {
          throw new Error(`Failed to load metadata (${response.status})`);
        }
        return response.json();
      }),
    ])
		// 변수 추가
      .then(([model, doorGltf, chairGltf, tableGltf, storageGltf, metadata]) => {
        if (!isMounted) {
          disposeScene(model);
          disposeScene(doorGltf.scene);
          disposeScene(chairGltf.scene);
		  disposeScene(tableGltf.scene);
		  disposeScene(storageGltf.scene);
          return;
        }

        model.name = "RoomLayer";
        prepareRoomModel(model);
        worldGroup.add(model);
        wallColliders.push(...createWallColliders(model));

		// 카테고리 구별 로직 추가
        (metadata.objects || []).forEach((item, index) => {
          const category = (item.category || "").toLowerCase();
          const furniture =
            category === "chair"
              ? createEditableFurnitureModel(chairGltf.scene, item, index)
			  : category === "table"
      			? createEditableFurnitureModel(tableGltf.scene, item, index)
				: category === "storage"
      				? createEditableFurnitureModel(storageGltf.scene, item, index)
              		: createEditableFurniture(item, index);

          furnitureLayer.add(furniture.root);
          editableRoots.push(furniture.root);
          pickTargets.push(...furniture.pickTargets);
        });

        (metadata.doors || []).forEach((item, index) => {
          const door = createDoorModel(doorGltf.scene, item, index);
          referenceLayer.add(door.root);
          editableRoots.push(door.root);
          pickTargets.push(...door.pickTargets);
        });

        (metadata.windows || []).forEach((item) => {
          const [box, label] = createReferenceBox(item, "window", 0x4ba3c7);
          referenceLayer.add(box, label);
        });

        if (editableRoots[0]) selectObject(editableRoots[0]);
        if (!editableRoots.length) syncSceneState(null);
        frameObject(camera, controls, worldGroup);
        setStatus("");
      })
      .catch((caughtError) => {
        if (!isMounted) return;
        setStatus("");
        setError(
          caughtError instanceof Error ? caughtError.message : String(caughtError)
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
	  renderer.domElement.removeEventListener("pointerdown", handlePointerDown);
	  selectedObjectRef.current = null;
	  syncSelectedRef.current = null;
	  setCollisionSummary({ hasCollision: false, with: [] });
	  transformControls.detach();
	  transformControls.dispose();
	  transformControlsRef.current = null;
	  controls.dispose();
	  disposeScene(scene);
	  renderer.dispose();
	  root.replaceChildren();
	};
  }, []);

  return (
	<div style={{ position: "relative", width: "100%", height: "100vh" }}>
	  <style>{`
		.furniture-label,
		.reference-label {
		  color: #17211d;
		  font: 12px Arial, Helvetica, sans-serif;
		  text-shadow: 0 1px 2px white, 1px 0 2px white, -1px 0 2px white;
		  user-select: none;
		  pointer-events: none;
		  white-space: nowrap;
		}

		.reference-label {
		  color: #53615b;
		  font-size: 10px;
		}
	  `}</style>
	  <div ref={containerRef} style={{ position: "absolute", inset: 0 }} />
	  <aside
		style={{
		  position: "absolute",
		  left: 16,
		  top: 16,
		  width: "min(390px, calc(100% - 32px))",
		  maxHeight: "calc(100% - 32px)",
		  overflow: "auto",
		  padding: 14,
		  background: "rgba(255,255,255,.9)",
		  border: "1px solid rgba(0,0,0,.12)",
		  borderRadius: 8,
		  boxShadow: "0 10px 28px rgba(0,0,0,.14)",
		  backdropFilter: "blur(8px)",
		  color: "#242424",
		  fontFamily: "Arial, Helvetica, sans-serif",
		  overflowWrap: "anywhere",
		}}
	  >
		<h1 style={{ margin: "0 0 10px", fontSize: 18 }}>Furniture Edit</h1>
		<div style={{ display: "flex", gap: 8, marginBottom: 10 }}>
		  <button
			type="button"
			onClick={() => setMode("translate")}
			style={{
			  flex: 1,
			  height: 34,
			  border: "1px solid rgba(0,0,0,.16)",
			  borderRadius: 6,
			  background: mode === "translate" ? "#17211d" : "#fff",
			  color: mode === "translate" ? "#fff" : "#17211d",
			  cursor: "pointer",
			}}
		  >
			Move
		  </button>
		  <button
			type="button"
			onClick={() => setMode("rotate")}
			style={{
			  flex: 1,
			  height: 34,
			  border: "1px solid rgba(0,0,0,.16)",
			  borderRadius: 6,
			  background: mode === "rotate" ? "#17211d" : "#fff",
			  color: mode === "rotate" ? "#fff" : "#17211d",
			  cursor: "pointer",
			}}
		  >
			Rotate
		  </button>
		  <button
			type="button"
			onClick={resetSelectedObject}
			disabled={!selectedItem}
			style={{
			  flex: 1,
			  height: 34,
			  border: "1px solid rgba(0,0,0,.16)",
			  borderRadius: 6,
			  background: "#fff",
			  color: "#17211d",
			  cursor: selectedItem ? "pointer" : "default",
			  opacity: selectedItem ? 1 : 0.48,
			}}
		  >
			Reset
		  </button>
		</div>
		<p style={{ margin: "0 0 10px", fontSize: 13, lineHeight: 1.35 }}>
		  {editedItems.length} editable objects / {mode}
		</p>
		<div
		  style={{
			marginBottom: 10,
			padding: "8px 10px",
			borderRadius: 6,
			border: collisionSummary.hasCollision
			  ? "1px solid rgba(170,40,40,.38)"
			  : "1px solid rgba(30,80,50,.24)",
			background: collisionSummary.hasCollision
			  ? "rgba(217,75,75,.12)"
			  : "rgba(95,143,116,.12)",
			color: collisionSummary.hasCollision ? "#8c2020" : "#2d5c42",
			fontSize: 12,
			lineHeight: 1.35,
		  }}
		>
		  {collisionSummary.hasCollision
			? `Collision: ${collisionSummary.with.join(", ")}`
			: "Collision: clear"}
		</div>
		<pre
		  style={{
			margin: 0,
			padding: 10,
			maxHeight: 300,
			overflow: "auto",
			background: "rgba(23,33,29,.08)",
			borderRadius: 6,
			fontSize: 11,
			lineHeight: 1.35,
			whiteSpace: "pre-wrap",
		  }}
		>
		  {JSON.stringify(selectedItem || editedItems[0] || {}, null, 2)}
		</pre>
	  </aside>
	  {status && (
		<div
		  style={{
			position: "absolute",
			inset: 0,
			display: "grid",
			placeItems: "center",
			color: "#242424",
			fontFamily: "Arial, Helvetica, sans-serif",
			pointerEvents: "none",
		  }}
		>
		  {status}
		</div>
	  )}
	  {error && (
		<pre
		  style={{
			position: "absolute",
			left: 18,
			right: 18,
			bottom: 18,
			margin: 0,
			padding: "12px 14px",
			background: "#fff0f0",
			color: "#7a1111",
			border: "1px solid #d7aaaa",
			borderRadius: 8,
			whiteSpace: "pre-wrap",
		  }}
		>
		  {error}
		</pre>
	  )}
	</div>
  );
}
