import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import {
  CSS2DObject,
  CSS2DRenderer,
} from "three/examples/jsm/renderers/CSS2DRenderer.js";
import {
  getRoomMetadataUrl,
  getRoomModelUrl,
  loadSceneConfig,
  referenceFallbackThickness,
  sceneColor,
  wallConfigBoolean,
} from "../scene/sceneConfig";
import {
  fetchJson,
  findModelTemplate,
  loadGltfModel,
  loadModelTemplates,
  loadUsdRoomModel,
  saveMetadataJson,
} from "../scene/sceneLoaders";
import { columnsFromMatrix, disposeScene, frameObject } from "../scene/threeUtils";
import {
  createReplayableMetadataJson,
  createRoomModelFromJson,
  objectToEditableJson,
} from "../scene/roomMetadata";
import {
  canTransformObject,
  clampObjectToWallBoundary,
  initializeWallConstraints,
  objectIntersectsWalls,
  refreshCollisionState,
  rememberValidTransform,
} from "../scene/collision";
import {
  createDoorModel,
  createEditableFurniture,
  createEditableFurnitureModel,
  createWindowModel,
} from "../scene/objectFactory";
import {
  createWallColliderVisuals,
  createWallColliders,
  prepareRoomModel,
} from "../scene/wallColliders";

const DEFAULT_FURNITURE_DIMENSIONS = { x: 0.8, y: 0.8, z: 0.8 };
const REFERENCE_CATEGORIES = new Set(["door", "window"]);

function normalizedDimensions(dimensions = {}) {
  return {
    x: Math.max(Number(dimensions.x) || DEFAULT_FURNITURE_DIMENSIONS.x, 0.04),
    y: Math.max(Number(dimensions.y) || DEFAULT_FURNITURE_DIMENSIONS.y, 0.04),
    z: Math.max(Number(dimensions.z) || DEFAULT_FURNITURE_DIMENSIONS.z, 0.04),
  };
}

function normalizedReferenceDimensions(category, dimensions = {}) {
  const fallbackThickness = referenceFallbackThickness(category);
  const thickness = Number(dimensions.z);

  return {
    x: Math.max(Number(dimensions.x) || DEFAULT_FURNITURE_DIMENSIONS.x, 0.04),
    y: Math.max(Number(dimensions.y) || DEFAULT_FURNITURE_DIMENSIONS.y, 0.04),
    z:
      Number.isFinite(thickness) &&
      thickness > 0 &&
      thickness <= fallbackThickness * 1.5
        ? thickness
        : fallbackThickness,
  };
}

function roundedTransform(
  position,
  quaternion = new THREE.Quaternion(),
  scale = new THREE.Vector3(1, 1, 1),
) {
  const matrix = new THREE.Matrix4().compose(
    position,
    quaternion,
    scale,
  );

  return {
    columns: columnsFromMatrix(matrix).map((column) =>
      column.map((value) => Number(value.toFixed(6))),
    ),
  };
}

function createFurnitureItemFromCatalog(
  catalogItem,
  position,
  quaternion = new THREE.Quaternion(),
  scale = new THREE.Vector3(1, 1, 1),
) {
  const dimensions = normalizedDimensions(catalogItem.dimensions);

  return {
    catalogId: catalogItem.id,
    name: catalogItem.name,
    category: catalogItem.category,
    path: catalogItem.path || catalogItem.modelUrl,
    modelUrl: catalogItem.modelUrl,
    dimensions,
    transform: roundedTransform(position, quaternion, scale),
  };
}

function estimateFloorY(metadataObjects, roomModel) {
  const objectFloorYs = (metadataObjects || [])
    .map((item) => {
      const y = Number(item.transform?.columns?.[3]?.[1]);
      const height = Number(item.dimensions?.y);
      return Number.isFinite(y) && Number.isFinite(height) ? y - height / 2 : null;
    })
    .filter((value) => value != null);

  if (objectFloorYs.length) {
    return Math.min(...objectFloorYs);
  }

  const bounds = new THREE.Box3().setFromObject(roomModel);
  return bounds.isEmpty() ? 0 : bounds.min.y;
}

function createDimensionLabel() {
  const element = document.createElement("div");
  element.className = "dimension-label";
  const label = new CSS2DObject(element);
  label.visible = false;
  return label;
}

function formatCentimeters(value) {
  return `${Math.max(Math.round(value * 100), 1)} cm`;
}

function stableDimensionsForObject(object, fallbackSize) {
  const dimensions = object?.userData.roomItem?.dimensions || {};

  return {
    width: Number(dimensions.x) || fallbackSize.x,
    height: Number(dimensions.y) || fallbackSize.y,
    depth: Number(dimensions.z) || fallbackSize.z,
  };
}

function applyWallPreviewOpacity(object, hidden) {
  const materials = Array.isArray(object.material)
    ? object.material
    : [object.material];

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
}

function updateViewFacingWalls(wallColliders, camera) {
  wallColliders.forEach((wall) => {
    const toCamera = camera.position.clone().sub(wall.obb.center).normalize();
    const hidden =
      wall.roomFacingNormal && toCamera.dot(wall.roomFacingNormal) < -0.2;

    applyWallPreviewOpacity(wall.object, hidden);
  });
}

function normalizeRotationDegrees(degrees) {
  const normalized = THREE.MathUtils.euclideanModulo(degrees + 180, 360) - 180;
  return Math.round(normalized);
}

function rotationDegreesFromObject(object) {
  if (!object) return 0;

  const euler = new THREE.Euler().setFromQuaternion(object.quaternion, "YXZ");
  return normalizeRotationDegrees(THREE.MathUtils.radToDeg(euler.y));
}

function isReplaceableObject(object) {
  if (!object) return false;

  return (
    canTransformObject(object) ||
    object.userData.sourceType === "door" ||
    object.userData.sourceType === "window"
  );
}

function createFallbackReferenceTemplate(sourceType) {
  const geometry = new THREE.BoxGeometry(1, 1, 1);
  const material = new THREE.MeshStandardMaterial({
    color: sceneColor(sourceType === "door" ? "doorReference" : "windowReference"),
    roughness: 0.72,
  });
  const mesh = new THREE.Mesh(geometry, material);
  const group = new THREE.Group();

  group.add(mesh);
  return group;
}

function captureCameraView(camera, controls) {
  return {
    position: camera.position.clone(),
    target: controls.target.clone(),
    up: camera.up.clone(),
    near: camera.near,
    far: camera.far,
  };
}

function applyCameraView(camera, controls, view) {
  camera.position.copy(view.position);
  camera.up.copy(view.up);
  camera.near = view.near;
  camera.far = view.far;
  camera.updateProjectionMatrix();
  controls.target.copy(view.target);
  controls.enableRotate = true;
  controls.update();
}

function applySkyviewCamera(viewController) {
  const { camera, controls, worldGroup } = viewController;
  const bounds = new THREE.Box3().setFromObject(worldGroup);
  if (bounds.isEmpty()) return;

  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const maxFloorSpan = Math.max(size.x, size.z, 1);
  const height =
    (maxFloorSpan / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2))) *
    1.5;

  camera.up.set(0, 0, -1);
  camera.position.set(
    center.x,
    center.y + Math.max(height, size.y + 2),
    center.z,
  );
  camera.near = Math.max(height / 1000, 0.01);
  camera.far = Math.max(height * 100, size.y + height + 100);
  camera.updateProjectionMatrix();
  controls.target.copy(center);
  controls.enableRotate = false;
  controls.update();
}

function applySkyviewMode(viewController, isSkyview) {
  if (!viewController) return;

  const { camera, controls } = viewController;
  if (isSkyview) {
    viewController.defaultView = captureCameraView(camera, controls);
    applySkyviewCamera(viewController);
    return;
  }

  if (viewController.defaultView) {
    applyCameraView(camera, controls, viewController.defaultView);
  }
}

export function useTestThreeEditor({ isSkyview = false } = {}) {
  const containerRef = useRef(null);
  const selectedObjectRef = useRef(null);
  const syncSelectedRef = useRef(null);
  const sourceMetadataRef = useRef(null);
  const roomModelRef = useRef(null);
  const viewControllerRef = useRef(null);
  const sceneActionsRef = useRef(null);
  const isSkyviewRef = useRef(isSkyview);
  const isReplacingSelectedRef = useRef(false);
  const [isSceneConfigReady, setSceneConfigReady] = useState(false);
  const [status, setStatus] = useState("Loading room model...");
  const [error, setError] = useState("");
  const [selectedItem, setSelectedItem] = useState(null);
  const [selectedRotationDegrees, setSelectedRotationDegreesState] =
    useState(0);
  const [isReplacingSelected, setReplacingSelected] = useState(false);
  const [editedItems, setEditedItems] = useState([]);
  const [collisionSummary, setCollisionSummary] = useState({
    hasCollision: false,
    with: [],
  });
  const canResetSelected = selectedItem?.sourceType === "object";
  const canDeleteSelected = selectedItem?.sourceType === "object";
  const canSaveJson = Boolean(sourceMetadataRef.current);

  function setReplaceMode(active) {
    isReplacingSelectedRef.current = active;
    setReplacingSelected(active);
  }

  useEffect(() => {
    isSkyviewRef.current = isSkyview;
    applySkyviewMode(viewControllerRef.current, isSkyview);
  }, [isSkyview]);

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

  async function addFurniture(catalogItem) {
    if (!sceneActionsRef.current) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    if (isReplacingSelectedRef.current && selectedObjectRef.current) {
      const replaced =
        await sceneActionsRef.current.replaceSelectedObject(catalogItem);
      if (replaced) setReplaceMode(false);
      return replaced;
    }

    return sceneActionsRef.current.addFurniture(catalogItem);
  }

  function deleteSelectedObject() {
    if (!sceneActionsRef.current) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.deleteSelectedObject();
  }

  function rotateSelectedObject() {
    if (!sceneActionsRef.current) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.rotateSelectedObject();
  }

  function setSelectedRotationDegrees(degrees) {
    if (!sceneActionsRef.current?.setSelectedRotationDegrees) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.setSelectedRotationDegrees(degrees);
  }

  function startReplaceSelectedObject() {
    if (!isReplaceableObject(selectedObjectRef.current)) return false;

    setReplaceMode(true);
    setError("");
    setStatus("왼쪽 목록에서 교체할 가구를 선택하세요.");
    return true;
  }

  async function saveEditedSceneJson() {
    if (!sourceMetadataRef.current || !roomModelRef.current) {
      setStatus("");
      setError("저장할 3D 편집 데이터가 아직 준비되지 않았습니다.");
      return false;
    }

    const replayableMetadata = createReplayableMetadataJson(
      sourceMetadataRef.current,
      editedItems,
      roomModelRef.current,
    );

    setError("");
    setStatus("Saving JSON...");

    try {
      await saveMetadataJson(getRoomMetadataUrl(), replayableMetadata);
      sourceMetadataRef.current = replayableMetadata;
      setStatus("JSON saved.");
      window.setTimeout(() => setStatus(""), 1200);
      return true;
    } catch (caughtError) {
      setStatus("");
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : String(caughtError),
      );
      return false;
    }
  }

  useEffect(() => {
    if (!containerRef.current) return undefined;

    let isMounted = true;

    if (!isSceneConfigReady) {
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
    let nextObjectIndex = 0;
    const editableRoots = [];
    const referenceRoots = [];
    const pickTargets = [];
    const wallColliders = [];
    const root = containerRef.current;
    const width = root.clientWidth || window.innerWidth;
    const height = root.clientHeight || window.innerHeight;

    root.replaceChildren();
    setError("");
    setSelectedItem(null);
    setSelectedRotationDegreesState(0);
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
    viewControllerRef.current = {
      camera,
      controls,
      worldGroup,
      defaultView: null,
    };

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
    const dimensionLabels = {
      width: createDimensionLabel(),
      depth: createDimensionLabel(),
      height: createDimensionLabel(),
    };
    let activeInteraction = null;

    selectionRing.rotation.x = -Math.PI / 2;
    selectionRing.renderOrder = 30;
    selectionHandle.renderOrder = 31;
    selectionLine.renderOrder = 30;
    selectionRing.visible = false;
    selectionHandle.visible = false;
    selectionLine.visible = false;
    selectionHandle.userData.controlType = "rotate";
    selectionLayer.add(
      selectionRing,
      selectionLine,
      selectionHandle,
      dimensionLabels.width,
      dimensionLabels.depth,
      dimensionLabels.height,
    );
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
        Object.values(dimensionLabels).forEach((label) => {
          label.visible = false;
        });
        selectionHandle.userData.editableRoot = null;
        return;
      }

      const bounds = new THREE.Box3().setFromObject(object);
      if (bounds.isEmpty()) {
        selectionRing.visible = false;
        selectionHandle.visible = false;
        selectionLine.visible = false;
        Object.values(dimensionLabels).forEach((label) => {
          label.visible = false;
        });
        selectionHandle.userData.editableRoot = null;
        return;
      }

      const size = bounds.getSize(new THREE.Vector3());
      const stableSize = stableDimensionsForObject(object, size);
      const radius = Math.max(0.35, Math.max(size.x, size.z) * 0.58 + 0.18);
      const baseY = bounds.min.y + 0.025;
      const labelY = bounds.min.y + 0.08;

      selectionRing.position.set(object.position.x, baseY, object.position.z);
      selectionRing.scale.set(radius, radius, 1);
      selectionRing.visible = true;
      dimensionLabels.width.element.textContent = formatCentimeters(
        stableSize.width,
      );
      dimensionLabels.depth.element.textContent = formatCentimeters(
        stableSize.depth,
      );
      dimensionLabels.height.element.textContent = formatCentimeters(
        stableSize.height,
      );
      dimensionLabels.width.position.set(
        (bounds.min.x + bounds.max.x) / 2,
        labelY,
        bounds.max.z + 0.12,
      );
      dimensionLabels.depth.position.set(
        bounds.max.x + 0.12,
        labelY,
        (bounds.min.z + bounds.max.z) / 2,
      );
      dimensionLabels.height.position.set(
        bounds.max.x + 0.12,
        (bounds.min.y + bounds.max.y) / 2,
        bounds.min.z - 0.12,
      );
      Object.values(dimensionLabels).forEach((label) => {
        label.visible = true;
      });
      selectionHandle.visible = false;
      selectionLine.visible = false;
      selectionHandle.userData.editableRoot = null;
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
      const exportedItems = [...editableRoots, ...referenceRoots].map(
        objectToEditableJson,
      );

      setEditedItems(exportedItems);
      setSelectedItem(
        selectedObject ? objectToEditableJson(selectedObject) : null,
      );
      setSelectedRotationDegreesState(rotationDegreesFromObject(selectedObject));
      setCollisionSummary({
        hasCollision: collisions.length > 0,
        with: collisions,
      });
      updateSelectionOverlay(selectedObject);
    }

    function selectObject(object) {
      selectedObjectRef.current = object;
      setReplaceMode(false);

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

      const editableHit =
        hits.find((hit) => canTransformObject(hit.object.userData.editableRoot)) ||
        hits[0];
      const object = editableHit.object.userData.editableRoot;
      selectObject(object);

      if (canTransformObject(object)) {
        if (
          object.userData.startsInWallCollision &&
          objectIntersectsWalls(object, wallColliders)
        ) {
          object.userData.ignoreWallConstraint = true;
        }
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
          loadModelTemplates(),
          metadata,
        ]),
      )
      // 변수 추가
      .then(async ([model, modelTemplates, metadata]) => {
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
        const floorY = estimateFloorY(metadata.objects, roomModel);
        wallColliders.push(...createWallColliders(roomModel));
        if (wallConfigBoolean("showColliderDebug")) {
          referenceLayer.add(createWallColliderVisuals(wallColliders));
        }

        const modelTemplatePromises = new Map();

        function loadModelTemplateForItem(item) {
          const modelUrl = item.modelUrl || item.path;
          if (modelUrl) {
            if (!modelTemplatePromises.has(modelUrl)) {
              modelTemplatePromises.set(
                modelUrl,
                loadGltfModel(modelUrl, item.name || item.category),
              );
            }

            return modelTemplatePromises
              .get(modelUrl)
              .then((gltf) => gltf.scene);
          }

          const modelTemplate = findModelTemplate(modelTemplates, item.category);
          return Promise.resolve(modelTemplate?.gltf.scene || null);
        }

        async function createFurnitureFromItem(item, index) {
          const modelTemplate = await loadModelTemplateForItem(item);
          return modelTemplate
            ? createEditableFurnitureModel(modelTemplate, item, index)
            : createEditableFurniture(item, index);
        }

        async function createReferenceFromItem(item, index, sourceType) {
          const referenceItem = { ...item, category: sourceType };
          const modelTemplate =
            (await loadModelTemplateForItem(referenceItem)) ||
            createFallbackReferenceTemplate(sourceType);

          return sourceType === "door"
            ? createDoorModel(modelTemplate, referenceItem, index)
            : createWindowModel(modelTemplate, referenceItem, index);
        }

        const furnitureItems = await Promise.all(
          (metadata.objects || []).map((item, index) =>
            createFurnitureFromItem(item, index),
          ),
        );

        if (!isMounted) {
          furnitureItems.forEach((furniture) => disposeScene(furniture.root));
          return;
        }

        furnitureItems.forEach((furniture) => {
          furnitureLayer.add(furniture.root);
          editableRoots.push(furniture.root);
          pickTargets.push(...furniture.pickTargets);
        });

        nextObjectIndex = (metadata.objects || []).length;

        function addFurnitureToScene(furniture, insertAt = editableRoots.length) {
          furnitureLayer.add(furniture.root);
          editableRoots.splice(insertAt, 0, furniture.root);
          pickTargets.push(...furniture.pickTargets);
          initializeWallConstraints([furniture.root], wallColliders);
          selectObject(furniture.root);
        }

        function removeEditableObject(object) {
          const objectIndex = editableRoots.indexOf(object);
          if (objectIndex >= 0) {
            editableRoots.splice(objectIndex, 1);
          }

          for (let index = pickTargets.length - 1; index >= 0; index -= 1) {
            if (pickTargets[index].userData.editableRoot === object) {
              pickTargets.splice(index, 1);
            }
          }

          object.parent?.remove(object);
          disposeScene(object);
          return objectIndex;
        }

        function addReferenceToScene(reference, insertAt = referenceRoots.length) {
          referenceLayer.add(reference.root);
          referenceRoots.splice(insertAt, 0, reference.root);
          pickTargets.push(...reference.pickTargets);
          selectObject(reference.root);
        }

        function removeReferenceObject(object) {
          const objectIndex = referenceRoots.indexOf(object);
          if (objectIndex >= 0) {
            referenceRoots.splice(objectIndex, 1);
          }

          for (let index = pickTargets.length - 1; index >= 0; index -= 1) {
            if (pickTargets[index].userData.editableRoot === object) {
              pickTargets.splice(index, 1);
            }
          }

          object.parent?.remove(object);
          disposeScene(object);
          return objectIndex;
        }

        sceneActionsRef.current = {
          addFurniture: async (catalogItem) => {
            if (!catalogItem) return false;
            if (REFERENCE_CATEGORIES.has(catalogItem.category)) {
              setStatus("");
              setError("문과 창문은 기존 문/창문을 선택한 뒤 교체로 적용하세요.");
              return false;
            }

            setError("");
            setStatus(`Adding ${catalogItem.name || "furniture"}...`);

            try {
              const dimensions = normalizedDimensions(catalogItem.dimensions);
              const target = controls.target.clone();
              const position = new THREE.Vector3(
                target.x,
                floorY + dimensions.y / 2,
                target.z,
              );
              const item = createFurnitureItemFromCatalog(
                catalogItem,
                position,
              );
              const objectIndex = nextObjectIndex;
              nextObjectIndex += 1;
              const furniture = await createFurnitureFromItem(item, objectIndex);

              if (!isMounted) {
                disposeScene(furniture.root);
                return false;
              }

              addFurnitureToScene(furniture);
              setStatus("");
              return true;
            } catch (caughtError) {
              setStatus("");
              setError(
                caughtError instanceof Error
                  ? caughtError.message
                  : String(caughtError),
              );
              return false;
            }
          },
          replaceSelectedObject: async (catalogItem) => {
            const object = selectedObjectRef.current;
            if (!catalogItem || !isReplaceableObject(object)) return false;

            const sourceType = object.userData.sourceType;
            if (
              sourceType === "object" &&
              REFERENCE_CATEGORIES.has(catalogItem.category)
            ) {
              setStatus("");
              setError("문/창문 모델은 기존 문/창문을 선택한 뒤 교체하세요.");
              return false;
            }
            if (
              REFERENCE_CATEGORIES.has(sourceType) &&
              !REFERENCE_CATEGORIES.has(catalogItem.category)
            ) {
              setStatus("");
              setError("문과 창문은 문/창문 모델로만 교체할 수 있습니다.");
              return false;
            }

            setError("");
            setStatus(`Replacing with ${catalogItem.name || "furniture"}...`);

            try {
              const isReferenceReplacement =
                REFERENCE_CATEGORIES.has(sourceType);
              const nextSourceType = isReferenceReplacement
                ? catalogItem.category
                : sourceType;
              const referenceDimensionSource =
                object.userData.roomItem?.dimensions || catalogItem.dimensions;
              const dimensions = isReferenceReplacement
                ? normalizedReferenceDimensions(
                    nextSourceType,
                    referenceDimensionSource,
                  )
                : normalizedDimensions(catalogItem.dimensions);
              const position = object.position.clone();
              if (sourceType === "object") {
                position.y = floorY + dimensions.y / 2;
              }
              const item = createFurnitureItemFromCatalog(
                { ...catalogItem, dimensions },
                position,
                object.quaternion.clone(),
                object.scale.clone(),
              );
              const sourceIndex =
                isReferenceReplacement && nextSourceType !== sourceType
                  ? referenceRoots.filter(
                      (root) => root.userData.sourceType === nextSourceType,
                    ).length
                  : object.userData.sourceIndex;
              const insertAt = isReferenceReplacement
                ? referenceRoots.indexOf(object)
                : editableRoots.indexOf(object);
              const nextObject = isReferenceReplacement
                ? await createReferenceFromItem(
                    item,
                    sourceIndex,
                    nextSourceType,
                  )
                : await createFurnitureFromItem(item, sourceIndex);

              if (!isMounted) {
                disposeScene(nextObject.root);
                return false;
              }

              if (isReferenceReplacement) {
                removeReferenceObject(object);
                addReferenceToScene(
                  nextObject,
                  insertAt >= 0 ? insertAt : referenceRoots.length,
                );
              } else {
                removeEditableObject(object);
                addFurnitureToScene(
                  nextObject,
                  insertAt >= 0 ? insertAt : editableRoots.length,
                );
              }
              setStatus("");
              return true;
            } catch (caughtError) {
              setStatus("");
              setError(
                caughtError instanceof Error
                  ? caughtError.message
                  : String(caughtError),
              );
              return false;
            }
          },
          rotateSelectedObject: () => {
            const object = selectedObjectRef.current;
            if (!isReplaceableObject(object)) return false;

            object.quaternion.premultiply(
              new THREE.Quaternion().setFromAxisAngle(upAxis, Math.PI / 2),
            );
            object.updateWorldMatrix(true, false);
            if (canTransformObject(object)) {
              clampObjectToWallBoundary(object, wallColliders);
            }
            syncSceneState(object);
            return true;
          },
          setSelectedRotationDegrees: (degrees) => {
            const object = selectedObjectRef.current;
            if (!isReplaceableObject(object)) return false;

            const normalized = normalizeRotationDegrees(Number(degrees) || 0);
            object.quaternion.setFromAxisAngle(
              upAxis,
              THREE.MathUtils.degToRad(normalized),
            );
            object.updateWorldMatrix(true, false);
            if (canTransformObject(object)) {
              clampObjectToWallBoundary(object, wallColliders);
            }
            syncSceneState(object);
            return true;
          },
          deleteSelectedObject: () => {
            const object = selectedObjectRef.current;
            if (
              !canTransformObject(object) ||
              object.userData.sourceType !== "object"
            ) {
              return false;
            }

            removeEditableObject(object);
            selectedObjectRef.current = null;
            setReplaceMode(false);
            syncSceneState(null);
            setStatus("Deleted furniture.");
            window.setTimeout(() => setStatus(""), 900);
            return true;
          },
        };

        const doorItems = await Promise.all(
          (metadata.doors || []).map((item, index) =>
            createReferenceFromItem(item, index, "door"),
          ),
        );
        const windowItems = await Promise.all(
          (metadata.windows || []).map((item, index) =>
            createReferenceFromItem(item, index, "window"),
          ),
        );

        if (!isMounted) {
          [...doorItems, ...windowItems].forEach((item) =>
            disposeScene(item.root),
          );
          return;
        }

        [...doorItems, ...windowItems].forEach((item) => {
          referenceLayer.add(item.root);
          referenceRoots.push(item.root);
          pickTargets.push(...item.pickTargets);
        });

        initializeWallConstraints(editableRoots, wallColliders);

        if (editableRoots[0]) selectObject(editableRoots[0]);
        if (!editableRoots.length) syncSceneState(null);
        frameObject(camera, controls, worldGroup);
        if (viewControllerRef.current) {
          viewControllerRef.current.defaultView = captureCameraView(
            camera,
            controls,
          );
          applySkyviewMode(viewControllerRef.current, isSkyviewRef.current);
        }
        setStatus("");
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

    function animate() {
      frameId = requestAnimationFrame(animate);
      controls.update();
      updateViewFacingWalls(wallColliders, camera);
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
      viewControllerRef.current = null;
      sceneActionsRef.current = null;
      setCollisionSummary({ hasCollision: false, with: [] });
      controls.dispose();
      disposeScene(scene);
      renderer.dispose();
      root.replaceChildren();
    };
  }, [isSceneConfigReady]);

  return {
    containerRef,
    status,
    error,
    selectedItem,
    selectedRotationDegrees,
    editedItems,
    isReplacingSelected,
    collisionSummary,
    canResetSelected,
    canDeleteSelected,
    canSaveJson,
    addFurniture,
    deleteSelectedObject,
    rotateSelectedObject,
    setSelectedRotationDegrees,
    resetSelectedObject,
    saveEditedSceneJson,
    startReplaceSelectedObject,
  };
}
