import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { CSS2DRenderer } from "three/examples/jsm/renderers/CSS2DRenderer.js";
import {
  getRoomMetadataUrl,
  getRoomModelUrl,
  hasSceneConfig,
  loadSceneConfig,
  sceneColor,
  wallConfigBoolean,
} from "../scene/sceneConfig";
import {
  fetchJson,
  findModelTemplate,
  loadModelTemplates,
  loadUsdRoomModel,
  modelCategoriesFromMetadata,
  requireModelTemplate,
  saveMetadataJson,
} from "../scene/sceneLoaders";
import { disposeScene, frameObject } from "../scene/threeUtils";
import {
  createReplayableMetadataJson,
  createRoomModelFromJson,
  objectToEditableJson,
} from "../scene/roomMetadata";
import {
  canTransformObject,
  clampObjectToWallBoundary,
  initializeWallConstraints,
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

export function useTestThreeEditor() {
  const containerRef = useRef(null);
  const selectedObjectRef = useRef(null);
  const syncSelectedRef = useRef(null);
  const sourceMetadataRef = useRef(null);
  const roomModelRef = useRef(null);
  const [isSceneConfigReady, setSceneConfigReady] = useState(
    hasSceneConfig(),
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

  async function saveEditedSceneJson() {
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
    } catch (caughtError) {
      setStatus("");
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : String(caughtError),
      );
    }
  }

  useEffect(() => {
    if (!containerRef.current) return undefined;

    let isMounted = true;

    if (!isSceneConfigReady || !hasSceneConfig()) {
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
      .then(([model, modelTemplates, metadata]) => {
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

  return {
    containerRef,
    status,
    error,
    selectedItem,
    editedItems,
    collisionSummary,
    canResetSelected,
    canSaveJson,
    resetSelectedObject,
    saveEditedSceneJson,
  };
}
