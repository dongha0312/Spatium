import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { CSS2DRenderer } from "three/examples/jsm/renderers/CSS2DRenderer.js";
import {
  getRoomMetadataUrl,
  getRoomModelUrl,
  optionalConfigBoolean,
  sceneColor,
  wallConfigBoolean,
} from "../scene/sceneConfig";
import {
  clearGltfModelCache,
  fetchJson,
  findModelTemplate,
  loadGltfModel,
  loadModelTemplates,
  loadUsdRoomModel,
  modelCategoriesFromMetadata,
  saveMetadataJson,
} from "../scene/sceneLoaders";
import {
  disposeScene,
  frameObject,
  matrixFromColumns,
} from "../scene/threeUtils";
import {
  createReplayableMetadataJson,
  createRoomModelFromJson,
  objectToEditableJson,
  serializeRoomModelToJson,
} from "../scene/roomMetadata";
import {
  canTransformObject,
  constrainedMovementBeforeWallCollision,
  getIntersectingWalls,
  hasWallCollision,
  initializeWallConstraints,
  objectIntersectsWalls,
  referenceCollidersFromRoots,
  refreshCollisionState,
  rememberValidTransform,
  setFurnitureVisualState,
  shouldCheckFurnitureCollision,
} from "../scene/collision";
import {
  createDecorFigure,
  createDoorModel,
  createEditableFurniture,
  createEditableFurnitureModel,
  createOpeningMarker,
  createWallInfillMesh,
  createWindowModel,
} from "../scene/objectFactory";
import {
  collectSupportMeshes,
  constrainedSupportPoint,
  figureBottomOffset,
  figureWorldSupportPoint,
  findSupportPointOnRay,
  isDecoratableModelPath,
  placeFigureAtSupportPoint,
} from "../scene/decorSurface";
import {
  applyDecorControlLimits,
  captureControlLimits,
  computeDecorView,
  restoreControlLimits,
} from "../scene/decorCamera";
import {
  captureCameraView,
  startCameraTransition,
  updateCameraTransition,
} from "../scene/cameraTransitions";
import {
  createWallColliderVisuals,
  createWallColliders,
  hideOutlierRoomMeshes,
  isUsdFloorMesh,
  prepareRoomModel,
} from "../scene/wallColliders";
import {
  calculateRoomMeasurements,
  framingBoundsFromMeasurements,
} from "../scene/roomMeasurements";
import {
  base64ToObjectUrl,
  createFallbackReferenceTemplate,
  createFurnitureItemFromCatalog,
  estimateFloorY,
  estimateRoomYawOffsetDegrees,
  formatCameraViewAngle,
  isReplaceableObject,
  normalizedDimensions,
  normalizedReferenceDimensions,
  recoverOutOfRoomFurniture,
  REFERENCE_CATEGORIES,
  rotationDegreesFromObject,
  roundedTransform,
} from "../scene/editorTransforms";
import {
  createDimensionLabel,
  createRoomDimensionLabel,
  formatCentimeters,
  formatPyung,
  formatSquareMeters,
  stableDimensionsForObject,
} from "../scene/measurementLabels";
import {
  createReferenceDebugLabel,
  initializeReferenceFacingNormal,
} from "../scene/referenceVisibility";
import {
  applyRoomWallColor,
  updateViewFacingWalls,
} from "../scene/wallVisibility";
import { applyRoomFloorColor } from "../scene/floorColor";
import { useSceneConfigStatus } from "./useSceneConfigStatus";
import { useSelectionState } from "./useSelectionState";
import {
  applySkyviewMode,
  useSkyviewMode,
} from "./useSkyviewMode";

// 카메라가 바닥 아래쪽으로 돌아가 위를 올려다보며(아래에서 위로) 바닥이 훤히 보이는
// 시점까지 가지 않도록 polar angle 상한을 둔다(180도 = 대상 바로 아래에서 수직으로
// 올려다보는 시점).
const FLOOR_VIEW_MAX_POLAR_ANGLE = THREE.MathUtils.degToRad(90);

// 피규어 기본 크기 상한(m). imgto3d로 저장된 사용자 가구의 치수가 실제 가구 스케일이어도
// 서랍장 위에 올릴 수 있는 소품 크기로 비율을 유지한 채 줄인다.
const FIGURE_MAX_DIMENSION = 0.35;
// 크기 슬라이더 범위(cm, 최대 변 기준).
const FIGURE_MIN_SIZE_CM = 5;
const FIGURE_MAX_SIZE_CM = 50;
const EDIT_HISTORY_LIMIT = 30;

// 피규어의 현재 크기(최대 변, cm). localObb는 scale 1 기준이므로 root scale을 곱한다.
function figureSizeCmForObject(object) {
  if (!object?.userData.isDecorFigure) return 0;

  const halfSize = object.userData.localObb?.halfSize;
  if (!halfSize) return 0;

  const baseMaxDimension = Math.max(halfSize.x, halfSize.y, halfSize.z) * 2;
  return Math.round(baseMaxDimension * object.scale.x * 100);
}

function objectSizeCmForObject(object) {
  if (!object || object.userData.sourceType !== "object") return 0;
  const halfSize = object.userData.localObb?.halfSize;
  if (!halfSize) return 0;
  const size = halfSize.clone().multiplyScalar(2).multiply(object.scale);
  return Math.round(Math.max(size.x, size.y, size.z) * 100);
}

// 선택된 오브젝트가 꾸미기 모드를 시작할 수 있는 대상인지 판단한다 — 모델 GLB가
// editable_furniture 폴더에 있는 일반 가구만(isDecoratableModelPath 참고).
function canDecorateObject(object) {
  const item = object?.userData.roomItem;
  return (
    object?.userData.sourceType === "object" &&
    isDecoratableModelPath(item?.path || item?.modelUrl)
  );
}

// 카탈로그 치수를 피규어 크기로 정규화한다. 비율은 유지하고 최대 변만
// FIGURE_MAX_DIMENSION으로 제한한다.
function figureDimensionsFromCatalog(dimensions) {
  const normalized = normalizedDimensions(dimensions);
  const maxDimension = Math.max(normalized.x, normalized.y, normalized.z);
  if (maxDimension <= FIGURE_MAX_DIMENSION) return normalized;

  const scale = FIGURE_MAX_DIMENSION / maxDimension;
  return {
    x: Number((normalized.x * scale).toFixed(4)),
    y: Number((normalized.y * scale).toFixed(4)),
    z: Number((normalized.z * scale).toFixed(4)),
  };
}

// 피규어를 서랍장 root의 자식으로 부착하고, 꾸미기 모드 선택/저장에 필요한 역참조를
// 등록한다. 이후 서랍장을 이동/회전하면 피규어도 함께 움직인다.
function attachFigureToTarget(targetRoot, figure) {
  targetRoot.userData.decorRoots = targetRoot.userData.decorRoots || [];
  targetRoot.userData.decorRoots.push(figure.root);
  figure.root.userData.hitBoxes = figure.pickTargets;
  targetRoot.add(figure.root);
  figure.root.updateWorldMatrix(true, false);
}

// 피규어를 서랍장에서 떼어내고 GPU 리소스를 정리한다.
function detachFigureFromTarget(figureRoot) {
  const parentRoot = figureRoot.parent;
  const decorRoots = parentRoot?.userData.decorRoots || [];
  const index = decorRoots.indexOf(figureRoot);
  if (index >= 0) decorRoots.splice(index, 1);

  parentRoot?.remove(figureRoot);
  disposeScene(figureRoot);
}

function debugConfigBoolean(name, defaultValue = false) {
  return optionalConfigBoolean(["debug", name], defaultValue);
}

// 3D 에디터의 핵심 훅. Three.js scene/camera/renderer 생성부터 방/가구/문/창문 로딩,
// 포인터 기반 선택·이동·회전, 벽 충돌, 저장까지 편집 세션 전체를 담당한다.
// 실제 씬 생성/조작 로직은 아래 useEffect 안에서 이뤄지고, 그 안의 sceneActionsRef에
// 담긴 함수들을 이 훅의 바깥쪽 wrapper 함수(addFurniture, rotateSelectedObject 등)가
// 호출하는 구조다 — sceneActionsRef가 null이면(씬이 아직 준비 안 됐으면) 에러 처리한다.
export function useRoomSceneEditor({
  isSkyview = false,
  isPersonView = false,
  showMeasurements = false,
  wallColor = null,
  floorColor = null,
  roomScene = null,
  onSceneChanged,
  onFloorColorLoaded,
} = {}) {
  const containerRef = useRef(null);
  const syncSelectedRef = useRef(null);
  const syncRoomMeasurementsRef = useRef(null);
  const roomMeasurementsRef = useRef(null);
  const sourceMetadataRef = useRef(null);
  const roomModelRef = useRef(null);
  const viewControllerRef = useRef(null);
  const sceneActionsRef = useRef(null);
  const showMeasurementsRef = useRef(showMeasurements);
  const isPersonViewRef = useRef(isPersonView);
  const wallColorRef = useRef(wallColor);
  const floorColorRef = useRef(floorColor);
  const onSceneChangedRef = useRef(onSceneChanged);
  const onFloorColorLoadedRef = useRef(onFloorColorLoaded);
  const { isSceneConfigReady, setStatus, error, setError } =
    useSceneConfigStatus();
  const {
    selectedObjectRef,
    isReplacingSelectedRef,
    selectedItem,
    setSelectedItem,
    selectedRotationDegrees,
    setSelectedRotationDegreesState,
    selectedElevationCm,
    setSelectedElevationCmState,
    selectedMaxElevationCm,
    setSelectedMaxElevationCmState,
    selectedSizeCm,
    setSelectedSizeCmState,
    isReplacingSelected,
    setReplaceMode,
    canResetSelected,
    canDeleteSelected,
  } = useSelectionState();
  const isSkyviewRef = useSkyviewMode(viewControllerRef, isSkyview);
  const [editedItems, setEditedItems] = useState([]);
  const [collisionSummary, setCollisionSummary] = useState({
    hasCollision: false,
    with: [],
  });
  const canSaveJson = Boolean(sourceMetadataRef.current);
  // 가구 추가 시 "바닥 클릭 배치" 모드. ref는 pointerdown 핸들러 안에서 즉시 참조하기
  // 위함이고, state는 안내 배너/커서 표시 등 화면 갱신용이다.
  const pendingPlacementRef = useRef(null);
  const [isPlacingFurniture, setIsPlacingFurniture] = useState(false);
  // 서랍장 꾸미기 모드 상태(UI 표시용). 실제 모드 컨텍스트(대상 서랍장, 표면 mesh 목록,
  // 복귀 시점)는 아래 useEffect 내부의 decorContext에 있다.
  const [decorModeState, setDecorModeState] = useState({
    active: false,
    targetName: "",
  });
  // 선택된 피규어의 현재 크기(최대 변, cm). 피규어가 아니면 0.
  const [selectedFigureSizeCm, setSelectedFigureSizeCmState] = useState(0);

  // 씬 메타데이터 snapshot을 이용한 편집 이력. past의 마지막 항목은 현재 상태다.
  const historyRef = useRef({ past: [], future: [] });
  // 방 geometry는 가구 transform 이력마다 복제하지 않고, 같은 방 상태를 가리키는
  // 작은 참조만 history entry에 남긴다.
  const historyRoomCacheRef = useRef(new Map());
  const historyRoomKeyRef = useRef(0);
  const historyApplyingRef = useRef(false);
  const metadataOverrideRef = useRef(null);
  const [historyVersion, setHistoryVersion] = useState(0);
  const [sceneRevision, setSceneRevision] = useState(0);

  function cloneSnapshot(snapshot) {
    if (!snapshot) return null;
    const { _spatiumRoom, ...compactSnapshot } = snapshot;
    return JSON.parse(JSON.stringify(compactSnapshot));
  }

  function trimHistoryRoomCache() {
    const activeRoomRefs = new Set(
      [...historyRef.current.past, ...historyRef.current.future]
        .map((snapshot) => snapshot?._spatiumRoomRef)
        .filter(Boolean),
    );

    historyRoomCacheRef.current.forEach((_roomJson, roomRef) => {
      if (!activeRoomRefs.has(roomRef)) {
        historyRoomCacheRef.current.delete(roomRef);
      }
    });
  }

  function registerHistoryCapture(captured) {
    if (!captured) return null;

    const sourceSnapshot = captured.snapshot || captured;
    if (!sourceSnapshot) return null;

    const snapshot = { ...sourceSnapshot };
    const roomJson = captured.roomJson || sourceSnapshot._spatiumRoom;
    delete snapshot._spatiumRoom;

    if (roomJson) {
      let roomRef = captured.roomRef || null;
      if (!roomRef) {
        for (const [cachedRoomRef, cachedRoomJson] of
          historyRoomCacheRef.current.entries()) {
          if (cachedRoomJson === roomJson) {
            roomRef = cachedRoomRef;
            break;
          }
        }
      }

      if (!roomRef) {
        roomRef = `room-${++historyRoomKeyRef.current}`;
        historyRoomCacheRef.current.set(roomRef, roomJson);
      } else if (!historyRoomCacheRef.current.has(roomRef)) {
        historyRoomCacheRef.current.set(roomRef, roomJson);
      }

      snapshot._spatiumRoomRef = roomRef;
    } else {
      snapshot._spatiumRoomRef = null;
    }

    return snapshot;
  }

  function materializeHistorySnapshot(snapshot) {
    if (!snapshot) return null;

    const roomRef = snapshot._spatiumRoomRef;
    const roomJson = roomRef
      ? historyRoomCacheRef.current.get(roomRef)
      : null;
    if (!roomJson) return snapshot;

    const { _spatiumRoomRef, ...metadata } = snapshot;
    return { ...metadata, _spatiumRoom: roomJson };
  }

  function snapshotSignature(snapshot) {
    if (!snapshot) return "";
    const normalized = cloneSnapshot(snapshot);
    if (normalized?._spatiumExport) {
      normalized._spatiumExport.exportedAt = "";
    }
    return JSON.stringify(normalized);
  }

  function recordHistory() {
    if (historyApplyingRef.current) return;
    const captured = sceneActionsRef.current?.captureHistorySnapshot?.();
    const snapshot = registerHistoryCapture(captured);
    if (!snapshot) return;

    const history = historyRef.current;
    const last = history.past[history.past.length - 1];
    if (last && snapshotSignature(last) === snapshotSignature(snapshot)) {
      return;
    }

    history.past.push(cloneSnapshot(snapshot));
    if (history.past.length > EDIT_HISTORY_LIMIT) history.past.shift();
    history.future = [];
    trimHistoryRoomCache();
    setHistoryVersion((value) => value + 1);
  }

  function applyHistorySnapshot(snapshot, previousSnapshot = null) {
    if (!snapshot) return false;

    // 이동·회전·높이·크기 조정처럼 씬 구조가 그대로인 변경은 전체 씬을
    // 재생성하지 않고 기존 Object3D의 transform만 갱신한다.
    if (
      previousSnapshot &&
      sceneActionsRef.current?.applySnapshotDiff?.(
        snapshot,
        previousSnapshot,
      )
    ) {
      return true;
    }

    historyApplyingRef.current = true;
    metadataOverrideRef.current = materializeHistorySnapshot(snapshot);
    setSceneRevision((value) => value + 1);
    return true;
  }

  function undo() {
    const history = historyRef.current;
    if (history.past.length < 2) return false;
    const current = history.past.pop();
    history.future.push(current);
    const target = history.past[history.past.length - 1];
    trimHistoryRoomCache();
    setHistoryVersion((value) => value + 1);
    return applyHistorySnapshot(target, current);
  }

  function redo() {
    const history = historyRef.current;
    if (!history.future.length) return false;
    const target = history.future.pop();
    const current = history.past[history.past.length - 1];
    history.past.push(target);
    trimHistoryRoomCache();
    setHistoryVersion((value) => value + 1);
    return applyHistorySnapshot(target, current);
  }

  function markSceneChanged() {
    onSceneChangedRef.current?.();
    recordHistory();
  }

  useEffect(() => {
    isPersonViewRef.current = isPersonView;
    sceneActionsRef.current?.setPersonView?.(isPersonView);
  }, [isPersonView]);

  useEffect(() => {
    showMeasurementsRef.current = showMeasurements;
    syncSelectedRef.current?.();
    syncRoomMeasurementsRef.current?.();
  }, [showMeasurements]);

  useEffect(() => {
    wallColorRef.current = wallColor;
    sceneActionsRef.current?.setWallColor?.(wallColor);
    if (sceneActionsRef.current) markSceneChanged();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wallColor]);

  useEffect(() => {
    floorColorRef.current = floorColor;
    sceneActionsRef.current?.setFloorColor?.(floorColor);
    if (sceneActionsRef.current) markSceneChanged();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [floorColor]);

  useEffect(() => {
    onSceneChangedRef.current = onSceneChanged;
  }, [onSceneChanged]);

  useEffect(() => {
    onFloorColorLoadedRef.current = onFloorColorLoaded;
  }, [onFloorColorLoaded]);

  // 가구 배치 모드 중 ESC로 취소할 수 있게 한다.
  useEffect(() => {
    if (!isPlacingFurniture) return undefined;

    function handleKeyDown(event) {
      if (event.key === "Escape") {
        cancelFurniturePlacement();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isPlacingFurniture]);

  // 오브젝트 하나의 최신 상태를 selectedItem/editedItems React state에 반영한다.
  function updateEditedItem(object) {
    const nextItem = objectToEditableJson(object);
    setSelectedItem(nextItem);
    setEditedItems((items) =>
      items.map((item) => (item.id === nextItem.id ? nextItem : item)),
    );
  }

  // 선택된 가구를 최초 로딩 당시의 transform(initialPosition 등)으로 되돌린다.
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
    markSceneChanged();
  }

  // 카탈로그 가구 클릭 시 호출된다. 교체 모드면 선택된 오브젝트를 즉시 교체하고, 아니면
  // "바닥 클릭 배치" 모드를 시작한다(customDimensions가 있으면 그 크기로 새로 추가될
  // 가구를 만든다). 실제 배치는 사용자가 바닥을 클릭한 시점에 이뤄진다.
  async function addFurniture(catalogItem, customDimensions) {
    if (!sceneActionsRef.current) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    // 꾸미기 모드 중에는 카탈로그 클릭이 "피규어 올려놓기/교체"로 동작한다.
    if (sceneActionsRef.current.isDecorModeActive?.()) {
      if (
        isReplacingSelectedRef.current &&
        selectedObjectRef.current?.userData.sourceType === "figure"
      ) {
        const replaced =
          await sceneActionsRef.current.replaceSelectedFigure(catalogItem);
        if (replaced) setReplaceMode(false);
        return replaced;
      }
      return sceneActionsRef.current.addFigureFromCatalog(catalogItem);
    }

    if (isReplacingSelectedRef.current && selectedObjectRef.current) {
      const replaced =
        await sceneActionsRef.current.replaceSelectedObject(catalogItem);
      if (replaced) setReplaceMode(false);
      return replaced;
    }

    return sceneActionsRef.current.beginPlaceFurniture(
      catalogItem,
      customDimensions,
    );
  }

  // 선택된 서랍장에 대해 꾸미기 모드를 시작한다(정면 시점 전환 + 피규어 편집).
  function enterDecorMode() {
    if (!sceneActionsRef.current?.enterDecorMode) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }
    return sceneActionsRef.current.enterDecorMode();
  }

  // 꾸미기 모드를 종료하고 원래 시점으로 복귀한다.
  function exitDecorMode() {
    return sceneActionsRef.current?.exitDecorMode?.() ?? false;
  }

  // 크기 슬라이더 값 변경 시 호출된다(피규어 전용, 최대 변 cm 기준).
  function setSelectedFigureSizeCm(sizeCm) {
    if (!sceneActionsRef.current?.setSelectedFigureSizeCm) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.setSelectedFigureSizeCm(sizeCm);
  }

  // 배치된 일반 가구의 최대 변(cm)을 균일하게 조절한다.
  function setSelectedSizeCm(sizeCm) {
    if (!sceneActionsRef.current?.setSelectedSizeCm) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.setSelectedSizeCm(sizeCm);
  }

  function commitSelectedTransformChange() {
    return sceneActionsRef.current?.commitSelectedTransformChange?.() || false;
  }

  // 진행 중인 "바닥 클릭 배치" 모드를 취소한다(ESC 키, 취소 버튼용).
  function cancelFurniturePlacement() {
    if (!sceneActionsRef.current) return false;
    return sceneActionsRef.current.cancelPlaceFurniture();
  }

  // 선택된 일반 가구를 삭제한다 (문/창문에는 적용 안 됨).
  function deleteSelectedObject() {
    if (!sceneActionsRef.current) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.deleteSelectedObject();
  }

  // 선택된 문/창문을 삭제한다. fillWithWall이 true면 그 자리를 벽으로 메우고,
  // false면 개구부(구멍)만 남긴다.
  function deleteSelectedReference(fillWithWall) {
    if (!sceneActionsRef.current) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.deleteSelectedReference(fillWithWall);
  }

  // 선택된 가구를 Y축으로 90도 회전시킨다(버튼용 — 슬라이더는 setSelectedRotationDegrees).
  function rotateSelectedObject() {
    if (!sceneActionsRef.current) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.rotateSelectedObject();
  }

  // 회전 슬라이더 값 변경 시 호출된다.
  function setSelectedRotationDegrees(degrees) {
    if (!sceneActionsRef.current?.setSelectedRotationDegrees) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.setSelectedRotationDegrees(degrees);
  }

  // 높이 슬라이더 값 변경 시 호출된다.
  function setSelectedElevationCm(elevationCm) {
    if (!sceneActionsRef.current?.setSelectedElevationCm) {
      setError("3D 편집기가 아직 준비되지 않았습니다.");
      return false;
    }

    return sceneActionsRef.current.setSelectedElevationCm(elevationCm);
  }

  // "교체" 버튼 클릭 시 교체 모드를 켠다. 이후 카탈로그 클릭이 addFurniture 대신
  // replaceSelectedObject로 라우팅된다.
  function startReplaceSelectedObject() {
    if (!isReplaceableObject(selectedObjectRef.current)) return false;

    setReplaceMode(true);
    setError("");
    setStatus("왼쪽 목록에서 교체할 가구를 선택하세요.");
    return true;
  }

  // 현재 편집 상태를 replayable metadata JSON으로 만들어 서버에 저장한다.
  async function saveEditedSceneJson(saveContext = {}) {
    if (!sourceMetadataRef.current || !roomModelRef.current) {
      setStatus("");
      setError("저장할 3D 편집 데이터가 아직 준비되지 않았습니다.");
      return false;
    }

    const replayableMetadata =
      sceneActionsRef.current?.captureSnapshot?.() ||
      createReplayableMetadataJson(
        sourceMetadataRef.current,
        editedItems,
        roomModelRef.current,
        floorColorRef.current,
      );

    setError("");
    setStatus("저장중...");

    try {
      await saveMetadataJson(replayableMetadata, {
        ...saveContext,
        area: roomMeasurementsRef.current?.area,
      });
      sourceMetadataRef.current = replayableMetadata;
      setStatus("저장완료.");
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

  // 이 훅의 핵심. isSceneConfigReady가 될 때까지 대기했다가 Three.js 씬을 새로 만든다.
  // roomScene/roomId가 바뀌면(의존성 배열 참고) 이 effect가 다시 실행되어 씬을 통째로
  // 재생성한다 — cleanup에서 이전 씬을 완전히 정리한다.
  useEffect(() => {
    if (!containerRef.current) return undefined;

    let isMounted = true;

    if (!isSceneConfigReady) return undefined;

    // 설정/방 데이터 검증은 WebGLRenderer를 만들기 전에 끝낸다. 여기서 예외가 나도
    // 아직 GPU context가 없으므로 effect cleanup 등록 전 누수가 발생하지 않는다.
    let roomModelObjectUrl = null;
    let roomModelUrl = null;
    let metadataPromise = null;
    try {
      roomModelUrl = roomScene?.model?.dataBase64
        ? (() => {
            roomModelObjectUrl = base64ToObjectUrl(
              roomScene.model.dataBase64,
              roomScene.model.contentType,
            );
            return roomModelObjectUrl;
          })()
        : getRoomModelUrl();
      metadataPromise = metadataOverrideRef.current
        ? Promise.resolve(metadataOverrideRef.current)
        : roomScene?.metadata
          ? Promise.resolve(roomScene.metadata)
          : fetchJson(getRoomMetadataUrl(), "room metadata");
    } catch (caughtError) {
      if (roomModelObjectUrl) {
        URL.revokeObjectURL(roomModelObjectUrl);
      }
      setStatus("");
      setError(
        caughtError instanceof Error ? caughtError.message : String(caughtError),
      );
      return undefined;
    }

    let frameId = 0;
    let nextObjectIndex = 0;
    let floorY = 0;
    let ceilingY = 0;
    let roomYawOffsetDegrees = 0;
    let personBounds = null;
    const editableRoots = [];
    const referenceRoots = [];
    const pickTargets = [];
    const wallColliders = [];
    const root = containerRef.current;

    // 가구 이동/회전/충돌 판정에서는 벽뿐 아니라 문/창문도 장애물로 취급한다. 개구부
    // 마커(sourceType: "opening")는 빈 구멍일 뿐 실제 장애물이 아니므로 제외한다 —
    // 문/창문으로 채워지기 전까지는 가구가 그 자리를 자유롭게 통과할 수 있어야 한다.
    //
    // 문/창문은 편집 중 움직이지 않으므로 결과(world OBB 계산 포함)를 캐시한다.
    // 벽 콜라이더나 문/창문 목록이 바뀌는 지점(추가/삭제/교체/벽으로 메우기/초기 로딩)에서
    // 반드시 invalidateActiveColliders()를 호출해야 한다.
    let cachedActiveColliders = null;
    // 벽/문/창문 구성이 바뀌면 다음 프레임에 벽 투명 처리(updateViewFacingWalls)를
    // 강제로 1회 실행하기 위한 플래그. 평소에는 카메라가 움직인 프레임에만 실행된다.
    let viewFacingWallsDirty = true;
    // 렌더 루프 최적화(on-demand rendering)용 플래그. 카메라가 그대로고 씬도 안 바뀐
    // 프레임에는 renderer.render()/labelRenderer.render() 자체를 건너뛰어, 사용자가
    // 아무것도 안 할 때 GPU를 계속 점유하지 않게 한다. 초기값 true — 최초 프레임은
    // 무조건 한 번 그린다. syncSceneState/syncDragState(가구 추가·이동·회전·삭제·교체,
    // undo/redo, 선택 변경 전반), resize, 벽/바닥 색상 변경, 초기 씬 로딩 완료 시점에서
    // true로 세팅되고, animate()가 렌더링한 직후 false로 리셋한다. 카메라 이동(오빗
    // 드래그/줌/댐핑 관성/1인칭 이동)은 아래 animate()의 cameraMoved로 별도 처리한다.
    let needsRender = true;
    const personKeys = new Set();
    let personLookPointerId = null;
    let personLastPointer = null;
    let personYaw = 0;
    let personPitch = -0.08;
    let personSavedView = null;
    let personSavedMaxDistance = null;
    let previousAnimationTime = performance.now();
    let cachedRoomModelJson = null;
    let hasCachedRoomModelJson = false;

    function invalidateRoomModelJsonCache() {
      cachedRoomModelJson = null;
      hasCachedRoomModelJson = false;
    }

    function getRoomModelJson() {
      if (!hasCachedRoomModelJson) {
        cachedRoomModelJson =
          serializeRoomModelToJson(
            roomModelRef.current,
            sourceMetadataRef.current?._spatiumRoom?.generatedFrom ||
              "api:room-scene",
          ) || null;
        hasCachedRoomModelJson = true;
      }

      return cachedRoomModelJson;
    }

    function invalidateActiveColliders() {
      cachedActiveColliders = null;
      // 콜라이더가 바뀌는 시점(문/창문 추가·삭제·교체, 벽으로 메우기, 초기 로딩)은
      // 벽/문/창문 투명 처리를 다시 계산해야 하는 시점과 정확히 일치하므로 함께 무효화한다.
      viewFacingWallsDirty = true;
    }

    function activeColliders() {
      if (!cachedActiveColliders) {
        cachedActiveColliders = wallColliders.concat(
          referenceCollidersFromRoots(
            referenceRoots.filter(
              (root) => root.userData.sourceType !== "opening",
            ),
          ),
        );
      }
      return cachedActiveColliders;
    }

    const width = root.clientWidth || window.innerWidth;
    const height = root.clientHeight || window.innerHeight;

    root.replaceChildren();
    setError("");
    setSelectedItem(null);
    setSelectedRotationDegreesState(0);
    setSelectedElevationCmState(0);
    setSelectedMaxElevationCmState(0);
    setSelectedSizeCmState(0);
    setEditedItems([]);
    setCollisionSummary({ hasCollision: false, with: [] });
    setDecorModeState({ active: false, targetName: "" });
    setSelectedFigureSizeCmState(0);
    setStatus("방 불러오는 중...");
    if (!historyApplyingRef.current) {
      historyRef.current = { past: [], future: [] };
    }

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
    labelRenderer.domElement.className = "room-scene-editor-label-layer";
    root.appendChild(labelRenderer.domElement);

    const showCameraAngle = debugConfigBoolean("showCameraAngle", false);
    const showReferenceLabels = debugConfigBoolean(
      "showReferenceLabels",
      false,
    );
    const cameraAngleBadge = showCameraAngle
      ? document.createElement("div")
      : null;
    if (cameraAngleBadge) {
      cameraAngleBadge.className = "room-scene-editor-camera-angle";
      cameraAngleBadge.textContent = formatCameraViewAngle(camera);
      root.appendChild(cameraAngleBadge);
    }
    const roomAreaBadge = document.createElement("div");
    roomAreaBadge.className = "room-scene-editor-room-area";
    roomAreaBadge.textContent = "";
    roomAreaBadge.hidden = true;
    root.appendChild(roomAreaBadge);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    // 관성(드래그 후 관성으로 계속 회전) 정도. 값이 클수록 감속이 빨라져 관성이 약해지고,
    // 작을수록(0에 가까울수록) 더 오래 미끄러지듯 회전한다. 1이면 관성 없이 즉시 멈춘다.
    controls.dampingFactor = 0.15;
    controls.rotateSpeed = 0.3;
    controls.maxPolarAngle = FLOOR_VIEW_MAX_POLAR_ANGLE;

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
      baseMaxDistance: null,
      roomYawOffsetDegrees: 0,
      transition: null,
      isInSkyview: false,
      isPersonView: false,
      personReturnView: null,
    };

    const furnitureLayer = new THREE.Group();
    furnitureLayer.name = "EditableFurnitureLayer";
    const referenceLayer = new THREE.Group();
    referenceLayer.name = "DoorWindowReferenceLayer";
    const selectionLayer = new THREE.Group();
    selectionLayer.name = "SelectionControlLayer";
    const wallDiagnosticLayer = new THREE.Group();
    wallDiagnosticLayer.name = "WallDiagnosticLayer";
    const roomMeasurementLayer = new THREE.Group();
    roomMeasurementLayer.name = "RoomMeasurementLayer";
    roomMeasurementLayer.visible = showMeasurementsRef.current;
    worldGroup.add(
      furnitureLayer,
      referenceLayer,
      selectionLayer,
      wallDiagnosticLayer,
      roomMeasurementLayer,
    );

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
    // 현재 진행 중인 드래그(이동/회전) 상태. null이면 드래그 중이 아님.
    let activeInteraction = null;
    // 서랍장 꾸미기 모드 컨텍스트. null이면 일반 편집 모드.
    // { target: 서랍장 root, supportMeshes: 표면 raycast 대상 mesh들,
    //   savedView: 복귀할 카메라 시점, savedLimits: 복귀할 OrbitControls 제한 }
    let decorContext = null;
    // Slider drags preview the selected object continuously and commit one
    // history entry when the interaction ends.
    let pendingTransformCommitObject = null;
    let pendingTransformSceneNotified = false;

    // 1인칭 시점은 OrbitControls를 잠시 비활성화하고 카메라를 눈높이에 고정한다.
    // 이동은 WASD/방향키, 시야 회전은 캔버스 드래그로 처리한다.
    function applyPersonView(enabled) {
      const controller = viewControllerRef.current;
      if (!controller) return;

      if (enabled) {
        if (pendingPlacementRef.current) {
          pendingPlacementRef.current = null;
          setIsPlacingFurniture(false);
          renderer.domElement.style.cursor = "default";
        }
        if (!controller.isPersonView) {
          personSavedView =
            controller.transition && controller.defaultView
              ? controller.defaultView
              : captureCameraView(camera, controls);
          personSavedMaxDistance = controls.maxDistance;
          controller.personReturnView = personSavedView;
        }
        const center =
          personBounds?.getCenter(new THREE.Vector3()) ||
          new THREE.Vector3(0, floorY, 0);
        const size = personBounds?.getSize(new THREE.Vector3());
        const offset = size ? Math.max(size.x, size.z) * 0.22 : 1.2;
        const personPosition = new THREE.Vector3(
          center.x,
          floorY + 1.6,
          center.z + offset,
        );
        personYaw = 0;
        personPitch = -0.08;
        const personDirection = new THREE.Vector3(0, 0, -1).applyEuler(
          new THREE.Euler(personPitch, personYaw, 0, "YXZ"),
        );
        const personTarget = personPosition.clone().add(personDirection);
        const personState = {
          position: personPosition,
          target: personTarget,
          up: new THREE.Vector3(0, 1, 0),
          near: 0.01,
          far: Math.max(camera.far, 100),
        };
        controls.enableRotate = false;
        controls.enablePan = false;
        controls.enableZoom = false;
        selectionLayer.visible = false;
        roomMeasurementLayer.visible = false;
        controller.isInSkyview = false;
        controller.isPersonView = true;
        startCameraTransition(
          controller,
          personState,
          Math.max(controls.maxDistance, personPosition.distanceTo(personTarget)),
          () => {
            controls.enabled = false;
            controls.enableRotate = false;
            controls.enablePan = false;
            controls.enableZoom = false;
            camera.rotation.order = "YXZ";
            camera.rotation.set(personPitch, personYaw, 0, "YXZ");
          },
        );
        viewFacingWallsDirty = true;
        return;
      }

      if (!controller.isPersonView) return;
      controller.isPersonView = false;
      selectionLayer.visible = true;
      roomMeasurementLayer.visible = showMeasurementsRef.current;
      // 1인칭 시점에서 Skyview를 바로 누른 경우에는 Skyview 훅이 이미 새
      // transition을 시작했으므로, 여기서 일반 시점 복귀 transition으로 덮어쓰지 않는다.
      if (isSkyviewRef.current) {
        personSavedView = null;
        personSavedMaxDistance = null;
        controller.personReturnView = null;
        viewFacingWallsDirty = true;
        return;
      }
      if (personSavedView) {
        const savedView = personSavedView;
        const savedMaxDistance = personSavedMaxDistance;
        controls.enableRotate = true;
        controls.enablePan = true;
        controls.enableZoom = true;
        if (Number.isFinite(savedMaxDistance)) {
          controls.maxDistance = savedMaxDistance;
        }
        startCameraTransition(
          controller,
          savedView,
          savedMaxDistance,
          () => {
            controls.enableRotate = true;
            controls.enablePan = true;
            controls.enableZoom = true;
            controls.enabled = true;
          },
        );
      } else {
        controls.enableRotate = true;
        controls.enablePan = true;
        controls.enableZoom = true;
        controls.enabled = true;
      }
      personSavedView = null;
      personSavedMaxDistance = null;
      controller.personReturnView = null;
      viewFacingWallsDirty = true;
    }

    function updatePersonMovement(deltaSeconds) {
      const controller = viewControllerRef.current;
      if (!controller?.isPersonView) return;

      const forwardInput =
        (personKeys.has("KeyW") || personKeys.has("ArrowUp") ? 1 : 0) -
        (personKeys.has("KeyS") || personKeys.has("ArrowDown") ? 1 : 0);
      const strafeInput =
        (personKeys.has("KeyD") || personKeys.has("ArrowRight") ? 1 : 0) -
        (personKeys.has("KeyA") || personKeys.has("ArrowLeft") ? 1 : 0);
      if (!forwardInput && !strafeInput) return;

      // 현재 카메라가 실제로 바라보는 방향을 기준으로 이동한다. yaw 변수만
      // 사용하는 대신 camera.getWorldDirection()을 읽어, 전환/드래그 직후에도
      // W는 화면 앞, D는 화면 오른쪽으로 일관되게 움직인다.
      const forward = new THREE.Vector3();
      camera.getWorldDirection(forward);
      forward.y = 0;
      if (forward.lengthSq() <= 1e-8) return;
      forward.normalize();
      const right = new THREE.Vector3()
        .crossVectors(forward, upAxis)
        .normalize();
      const movement = forward
        .multiplyScalar(forwardInput)
        .add(right.multiplyScalar(strafeInput));
      if (movement.lengthSq() > 1) movement.normalize();
      const speed = personKeys.has("ShiftLeft") || personKeys.has("ShiftRight")
        ? 4.2
        : 2.2;
      camera.position.addScaledVector(movement, speed * deltaSeconds);

      const radius = 0.28;
      if (personBounds && !personBounds.isEmpty()) {
        camera.position.x = THREE.MathUtils.clamp(
          camera.position.x,
          personBounds.min.x + radius,
          personBounds.max.x - radius,
        );
        camera.position.z = THREE.MathUtils.clamp(
          camera.position.z,
          personBounds.min.z + radius,
          personBounds.max.z - radius,
        );
      }
      camera.position.y = floorY + 1.6;
      camera.rotation.order = "YXZ";
      camera.rotation.set(personPitch, personYaw, 0, "YXZ");
    }

    // 꾸미기 모드에서 클릭/드래그로 선택할 수 있는 대상 — 현재 서랍장에 올려진
    // 피규어들의 투명 hitBox 목록.
    function decorPickTargets() {
      if (!decorContext) return [];
      return (decorContext.target.userData.decorRoots || []).flatMap(
        (figureRoot) => figureRoot.userData.hitBoxes || [],
      );
    }

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

    // showMeasurements prop에 따라 방 치수 레이어/면적 배지의 표시 여부를 맞춘다.
    function syncRoomMeasurementLayerVisibility() {
      const isVisible = showMeasurementsRef.current;
      roomMeasurementLayer.visible = isVisible;
      roomAreaBadge.hidden =
        !isVisible || !Number.isFinite(roomMeasurementsRef.current?.area);
    }

    // 방 치수 계산 결과(calculateRoomMeasurements)로부터 외곽선/눈금(tick)/치수 라벨과
    // 면적 배지를 만들어 roomMeasurementLayer에 채운다.
    function addRoomMeasurements(measurements) {
      roomMeasurementLayer.clear();
      roomMeasurementsRef.current = measurements || null;
      if (Number.isFinite(measurements?.area)) {
        roomAreaBadge.textContent = `면적 ${formatSquareMeters(measurements.area)}  ${formatPyung(measurements.area * 0.3025)}`;
        roomAreaBadge.hidden = !showMeasurementsRef.current;
      } else {
        roomAreaBadge.hidden = true;
      }
      if (!measurements?.outlineSegments?.length) return;

      const vertices = [];
      const center = measurements.center || { x: 0, z: 0 };
      const offsetDistance = 0.14;
      const tickLength = 0.18;

      measurements.outlineSegments.forEach((segment) => {
        const start = new THREE.Vector3(
          segment.start.x,
          segment.start.y,
          segment.start.z,
        );
        const end = new THREE.Vector3(
          segment.end.x,
          segment.end.y,
          segment.end.z,
        );
        const midpoint = start.clone().add(end).multiplyScalar(0.5);
        const outward = new THREE.Vector3(
          midpoint.x - center.x,
          0,
          midpoint.z - center.z,
        );

        if (outward.lengthSq() < 0.0001) {
          outward.set(end.z - start.z, 0, -(end.x - start.x));
        }

        outward.normalize();

        const direction = end.clone().sub(start).setY(0).normalize();
        const lineStart = start
          .clone()
          .addScaledVector(outward, offsetDistance)
          .add(new THREE.Vector3(0, 0.06, 0));
        const lineEnd = end
          .clone()
          .addScaledVector(outward, offsetDistance)
          .add(new THREE.Vector3(0, 0.06, 0));
        const tickAxis = new THREE.Vector3(-direction.z, 0, direction.x);
        const firstTickA = lineStart
          .clone()
          .addScaledVector(tickAxis, tickLength / 2);
        const firstTickB = lineStart
          .clone()
          .addScaledVector(tickAxis, -tickLength / 2);
        const secondTickA = lineEnd
          .clone()
          .addScaledVector(tickAxis, tickLength / 2);
        const secondTickB = lineEnd
          .clone()
          .addScaledVector(tickAxis, -tickLength / 2);

        vertices.push(
          lineStart.x,
          lineStart.y,
          lineStart.z,
          lineEnd.x,
          lineEnd.y,
          lineEnd.z,
          firstTickA.x,
          firstTickA.y,
          firstTickA.z,
          firstTickB.x,
          firstTickB.y,
          firstTickB.z,
          secondTickA.x,
          secondTickA.y,
          secondTickA.z,
          secondTickB.x,
          secondTickB.y,
          secondTickB.z,
        );

        const label = createRoomDimensionLabel(
          formatCentimeters(segment.length),
        );
        label.position
          .copy(midpoint)
          .addScaledVector(outward, offsetDistance + 0.12)
          .add(new THREE.Vector3(0, 0.12, 0));
        roomMeasurementLayer.add(label);
      });

      if (measurements.heightSegment) {
        const start = new THREE.Vector3(
          measurements.heightSegment.start.x,
          measurements.heightSegment.start.y,
          measurements.heightSegment.start.z,
        );
        const end = new THREE.Vector3(
          measurements.heightSegment.end.x,
          measurements.heightSegment.end.y,
          measurements.heightSegment.end.z,
        );
        const tickAxis = new THREE.Vector3(1, 0, 0);
        const tickLength = 0.18;
        const firstTickA = start
          .clone()
          .addScaledVector(tickAxis, tickLength / 2);
        const firstTickB = start
          .clone()
          .addScaledVector(tickAxis, -tickLength / 2);
        const secondTickA = end
          .clone()
          .addScaledVector(tickAxis, tickLength / 2);
        const secondTickB = end
          .clone()
          .addScaledVector(tickAxis, -tickLength / 2);

        vertices.push(
          start.x,
          start.y,
          start.z,
          end.x,
          end.y,
          end.z,
          firstTickA.x,
          firstTickA.y,
          firstTickA.z,
          firstTickB.x,
          firstTickB.y,
          firstTickB.z,
          secondTickA.x,
          secondTickA.y,
          secondTickA.z,
          secondTickB.x,
          secondTickB.y,
          secondTickB.z,
        );

        const label = createRoomDimensionLabel(
          formatCentimeters(measurements.height),
        );
        label.position
          .copy(start)
          .lerp(end, 0.5)
          .add(new THREE.Vector3(0.16, 0, 0));
        roomMeasurementLayer.add(label);
      }

      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute(
        "position",
        new THREE.Float32BufferAttribute(vertices, 3),
      );
      const line = new THREE.LineSegments(
        geometry,
        new THREE.LineBasicMaterial({
          color: 0x8b8f94,
          transparent: true,
          opacity: 0.78,
          depthTest: false,
        }),
      );
      line.renderOrder = 40;
      roomMeasurementLayer.add(line);
      syncRoomMeasurementLayerVisibility();
    }

    syncRoomMeasurementsRef.current = syncRoomMeasurementLayerVisibility;

    // 마우스/터치 이벤트 좌표를 정규화 좌표로 바꾸고 raycaster를 그 방향으로 세팅한다.
    function setPointerRay(event) {
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(mouse, camera);
    }

    // 포인터 ray가 "선택된 오브젝트 높이의 수평면"과 만나는 지점을 구한다. 이동/회전
    // 드래그 모두 이 평면 위에서 계산되므로, 높이(Y)는 드래그 중 절대 바뀌지 않는다.
    function intersectObjectFloor(event, object, target) {
      floorPlane.set(upAxis, -object.position.y);
      setPointerRay(event);
      return raycaster.ray.intersectPlane(floorPlane, target);
    }

    // 중심점 기준으로 바닥 위의 점이 이루는 각도 (드래그 회전 각도 계산용).
    function angleOnFloor(center, point) {
      return Math.atan2(point.x - center.x, point.z - center.z);
    }

    // 드래그 도중 포인터가 캔버스 밖으로 나가도 이벤트를 계속 받기 위한 포인터 캡처.
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

    // 씬 위에서 발생한 포인터 이벤트가 OrbitControls 등 다른 핸들러로 전파되지 않게 막는다.
    function stopSceneEvent(event) {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation?.();
    }

    // 선택 표시(고리, 회전 핸들, 치수 라벨)를 선택된 오브젝트 위치/크기에 맞춰 갱신한다.
    // 선택이 없으면 전부 숨긴다.
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
      // 피규어는 서랍장의 자식이라 position이 부모 로컬 좌표다 — 선택 고리는 월드
      // 좌표에 그려지므로 항상 월드 위치 기준으로 계산한다(일반 가구는 둘이 같다).
      const worldPosition = object.getWorldPosition(new THREE.Vector3());

      selectionRing.position.set(worldPosition.x, baseY, worldPosition.z);
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
        label.visible = showMeasurementsRef.current;
      });
      selectionHandle.visible = false;
      selectionLine.visible = false;
      selectionHandle.userData.editableRoot = null;
    }

    // 가구 드래그 이동을 시작한다. 포인터와 오브젝트 위치의 offset을 기억해서, 드래그
    // 중에도 클릭했던 지점 기준으로 자연스럽게 따라오게 한다.
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

    // 회전 핸들(selectionHandle) 드래그를 시작한다. 시작 각도/quaternion을 기억해두고
    // updateActiveInteraction에서 그 차이만큼 회전시킨다.
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

    // 꾸미기 모드에서 피규어 드래그 이동을 시작한다. 이동 자체는 서랍장 표면 raycast로
    // 계산되므로(updateActiveInteraction의 figure-move 분기) 바닥 평면 교차는 쓰지 않는다.
    function beginFigureMoveInteraction(event, figureRoot) {
      activeInteraction = {
        type: "figure-move",
        pointerId: event.pointerId,
        object: figureRoot,
      };
      controls.enabled = false;
      renderer.domElement.style.cursor = "grabbing";
      capturePointer(event.pointerId);
      return true;
    }

    // pointermove마다 호출된다. 이동 중이면 벽 충돌 제한을 적용해 위치를 갱신하고,
    // 회전 중이면 회전을 적용해보고 벽과 충돌하면 즉시 되돌린다.
    function updateActiveInteraction(event) {
      if (
        !activeInteraction ||
        event.pointerId !== activeInteraction.pointerId
      ) {
        return;
      }

      const { object } = activeInteraction;
      if (!object) return;

      // 피규어 드래그: 포인터 ray를 서랍장 표면에 쏴서, 위를 향한 면(상판/선반 바닥)이
      // 맞으면 그 지점으로 스냅한다(다른 층으로의 이동 포함). 포인터가 표면 밖(허공/옆면)
      // 으로 나가면 얼어붙는 대신, 현재 층 높이의 수평면과 포인터의 교차점을 목표로 삼아
      // 벽 충돌 이동 제한과 같은 sweep 방식으로 표면 가장자리까지 부드럽게 미끄러진다
      // (constrainedSupportPoint).
      if (activeInteraction.type === "figure-move") {
        if (!decorContext) return;

        setPointerRay(event);
        const support = findSupportPointOnRay(
          raycaster,
          decorContext.supportMeshes,
        );
        if (support) {
          placeFigureAtSupportPoint(object, support.point);
          rememberValidTransform(object);
        } else {
          const currentPoint = figureWorldSupportPoint(object);
          floorPlane.set(upAxis, -currentPoint.y);
          if (raycaster.ray.intersectPlane(floorPlane, floorHitPoint)) {
            const constrainedPoint = constrainedSupportPoint(
              object,
              decorContext.supportMeshes,
              floorHitPoint,
            );
            placeFigureAtSupportPoint(object, constrainedPoint);
            rememberValidTransform(object);
          }
        }
        updateSelectionOverlay(object);
        // 피규어 드래그는 syncDragState를 거치지 않으므로 여기서 직접 렌더를 요청한다
        // (안 그러면 needsRender가 false로 남아 드래그 중 화면이 멈춘 것처럼 보인다).
        needsRender = true;
        return;
      }

      if (!intersectObjectFloor(event, object, floorHitPoint)) return;

      if (activeInteraction.type === "move") {
        const targetPosition = floorHitPoint
          .clone()
          .add(activeInteraction.offset);
        targetPosition.y = activeInteraction.y;

        const movement = targetPosition.clone().sub(object.position);
        const adjustedMovement = constrainedMovementBeforeWallCollision(
          object,
          movement,
          activeColliders(),
        );
        object.position.add(adjustedMovement);
        object.position.y = activeInteraction.y;
      } else if (activeInteraction.type === "rotate") {
        const angle = angleOnFloor(activeInteraction.center, floorHitPoint);
        const delta = angle - activeInteraction.startAngle;
        const previousQuaternion = object.quaternion.clone();
        object.position.copy(activeInteraction.center);
        object.quaternion
          .copy(activeInteraction.startQuaternion)
          .premultiply(new THREE.Quaternion().setFromAxisAngle(upAxis, delta));
        object.updateWorldMatrix(true, false);
        if (hasWallCollision(object, activeColliders())) {
          object.quaternion.copy(previousQuaternion);
        }
      }

      object.updateWorldMatrix(true, false);
      rememberValidTransform(object);
      syncDragState(object);
    }

    // pointerup/cancel 시 드래그를 종료하고 변경사항이 있었음을 상위에 알린다.
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
      // 벽에 박힌 채 시작해 제약이 임시 해제돼 있던 가구를 사용자가 벽 밖으로
      // 꺼냈다면, 이 시점부터 정상 벽 제약을 다시 적용한다.
      if (
        object.userData.startsInWallCollision &&
        !objectIntersectsWalls(object, activeColliders())
      ) {
        object.userData.startsInWallCollision = false;
        object.userData.ignoreWallConstraint = false;
        rememberValidTransform(object);
      }
      syncSceneState(object, { changedObjects: [object] });
      markSceneChanged();
    }

    // 이전에 그려둔 벽 진단(충돌/차단) 시각화를 전부 지운다.
    function clearWallDiagnostics() {
      while (wallDiagnosticLayer.children.length) {
        const child = wallDiagnosticLayer.children.pop();
        disposeScene(child);
      }
    }

    function uniqueWalls(walls) {
      return [...new Set((walls || []).filter(Boolean))];
    }

    // 벽 목록으로 디버그 시각화를 만들어 wallDiagnosticLayer에 추가한다.
    function addWallDiagnosticVisuals(walls, options) {
      const uniqueWallColliders = uniqueWalls(walls);
      if (!uniqueWallColliders.length) return;

      wallDiagnosticLayer.add(
        createWallColliderVisuals(uniqueWallColliders, options),
      );
    }

    // 직전에 그린 벽 진단 시각화가 어떤 벽 조합이었는지 기록해서, 같은 조합이면
    // geometry 생성/파기를 건너뛴다(드래그 중 매 pointermove마다 호출되기 때문).
    let lastWallDiagnosticsKey = "";

    function wallDiagnosticsKey(object) {
      const keyFor = (walls) =>
        uniqueWalls(walls)
          .map(
            (wall) => `${wall.object?.uuid || ""}:${wall.triangleStart ?? ""}`,
          )
          .join(",");
      return `${keyFor(object.userData.intersectingWallColliders)}|${keyFor(
        object.userData.blockedWallColliders,
      )}`;
    }

    // 선택된 오브젝트가 현재 겹치고 있거나(intersecting) 이동이 막혔던(blocked) 벽을
    // showWallDiagnostics 설정이 켜져 있을 때만 시각화한다.
    function updateWallDiagnostics(object = selectedObjectRef.current) {
      const showDiagnostics =
        Boolean(object) &&
        optionalConfigBoolean(
          ["wallConstraints", "showWallDiagnostics"],
          true,
        );
      const key = showDiagnostics ? wallDiagnosticsKey(object) : "";
      if (key === lastWallDiagnosticsKey) return;

      lastWallDiagnosticsKey = key;
      clearWallDiagnostics();
      if (!showDiagnostics) return;

      addWallDiagnosticVisuals(object.userData.intersectingWallColliders, {
        name: "IntersectingWallDiagnosticLayer",
        color: sceneColor("collision"),
        opacityMultiplier: 1.35,
        renderOrderOffset: 40,
      });
      addWallDiagnosticVisuals(object.userData.blockedWallColliders, {
        name: "BlockedWallDiagnosticLayer",
        color: sceneColor("selectedEdge"),
        opacityMultiplier: 1.45,
        renderOrderOffset: 60,
      });
    }

    // 선택된 가구의 현재 높이(cm, 바닥 기준)와 슬라이더 최댓값(천장에 닿기 직전)을 계산한다.
    function elevationBoundsForObject(object) {
      // 피규어는 서랍장 표면 위에만 놓이므로 높이 슬라이더 대상이 아니다.
      if (
        !object ||
        !canTransformObject(object) ||
        object.userData.isDecorFigure
      ) {
        return { currentCm: 0, maxCm: 0 };
      }

      const halfHeight = object.userData.localObb?.halfSize?.y ?? 0;
      const restY = floorY + halfHeight;
      const maxY = Math.max(restY, ceilingY - halfHeight);

      return {
        currentCm: Math.round((object.position.y - restY) * 100),
        maxCm: Math.round((maxY - restY) * 100),
      };
    }

    // 씬이 바뀔 때마다(선택/이동/회전/추가/삭제 등) 호출되는 중앙 갱신 함수. 충돌 상태를
    // 다시 계산하고, React state(선택 정보/회전/높이/충돌 요약)를 동기화하고, 벽 진단과
    // 선택 오버레이 시각화까지 전부 최신 상태로 맞춘다.
    function syncSceneState(
      selectedObject = selectedObjectRef.current,
      options = {},
    ) {
      needsRender = true;
      const collisions = refreshCollisionState(
        editableRoots,
        selectedObject,
        activeColliders(),
        options.changedObjects || null,
      );
      const changedObjects = options.changedObjects;
      if (changedObjects) {
        const changedItems = changedObjects
          .filter(Boolean)
          .map(objectToEditableJson);
        const changedById = new Map(
          changedItems.map((item) => [item.id, item]),
        );
        setEditedItems((items) =>
          items.map((item) => changedById.get(item.id) || item),
        );
      } else {
        const exportedItems = [...editableRoots, ...referenceRoots].map(
          objectToEditableJson,
        );
        setEditedItems(exportedItems);
      }

      setSelectedItem(
        selectedObject ? objectToEditableJson(selectedObject) : null,
      );
      setSelectedRotationDegreesState(
        rotationDegreesFromObject(selectedObject, roomYawOffsetDegrees),
      );
      const elevationBounds = elevationBoundsForObject(selectedObject);
      setSelectedElevationCmState(elevationBounds.currentCm);
      setSelectedMaxElevationCmState(elevationBounds.maxCm);
      setSelectedSizeCmState(objectSizeCmForObject(selectedObject));
      setSelectedFigureSizeCmState(figureSizeCmForObject(selectedObject));
      setCollisionSummary({
        hasCollision: collisions.length > 0,
        with: collisions,
      });
      // 피규어는 editableRoots에 없어 refreshCollisionState의 시각 갱신 대상이 아니므로,
      // 선택 표시(노란 edge)를 여기서 직접 갱신한다.
      if (selectedObject?.userData.isDecorFigure) {
        setFurnitureVisualState(selectedObject, selectedObject);
      }
      updateWallDiagnostics(selectedObject);
      updateSelectionOverlay(selectedObject);
    }

    // 드래그(이동/회전) 중 매 pointermove마다 호출되는 경량 동기화. 움직이는 오브젝트
    // 하나의 충돌 상태/시각 표시(빨간 하이라이트), 벽 진단, 선택 오버레이만 갱신한다.
    // 전체 가구 재계산 + React state 동기화(syncSceneState)는 비용이 커서
    // endActiveInteraction(pointerup)으로 미룬다 — 드래그 중에는 다른 가구가 움직이지
    // 않고, 정보 패널에 표시되는 값(치수/각도/높이)도 이동으로는 바뀌지 않기 때문에
    // 화면에 보이는 결과는 동일하다.
    function syncDragState(object) {
      needsRender = true;
      if (shouldCheckFurnitureCollision(object)) {
        const intersectingWalls = getIntersectingWalls(
          object,
          activeColliders(),
        );
        object.userData.intersectingWallColliders = intersectingWalls;
        object.userData.collisions = intersectingWalls.length ? ["wall"] : [];
        setFurnitureVisualState(object, selectedObjectRef.current);
      }
      updateWallDiagnostics(object);
      updateSelectionOverlay(object);
    }

    // 오브젝트를 선택 상태로 만든다(또는 null로 선택 해제). 교체 모드는 항상 해제된다.
    // Range controls can emit dozens of values during one drag. Keep the
    // preview scoped to the selected object and defer the full scene export
    // plus history capture until pointer/keyboard interaction ends.
    function syncSelectedTransformPreview(object) {
      if (!object) return;

      if (shouldCheckFurnitureCollision(object)) {
        const intersectingWalls = getIntersectingWalls(
          object,
          activeColliders(),
        );
        object.userData.intersectingWallColliders = intersectingWalls;
        object.userData.collisions = intersectingWalls.length ? ["wall"] : [];
        setFurnitureVisualState(object, selectedObjectRef.current);
        setCollisionSummary({
          hasCollision: intersectingWalls.length > 0,
          with: intersectingWalls,
        });
      } else {
        setCollisionSummary({ hasCollision: false, with: [] });
      }

      setSelectedItem(objectToEditableJson(object));
      setSelectedRotationDegreesState(
        rotationDegreesFromObject(object, roomYawOffsetDegrees),
      );
      const elevationBounds = elevationBoundsForObject(object);
      setSelectedElevationCmState(elevationBounds.currentCm);
      setSelectedMaxElevationCmState(elevationBounds.maxCm);
      setSelectedSizeCmState(objectSizeCmForObject(object));
      setSelectedFigureSizeCmState(figureSizeCmForObject(object));
      updateWallDiagnostics(object);
      updateSelectionOverlay(object);
    }

    function markTransformPreview(object) {
      pendingTransformCommitObject = object;
      if (!pendingTransformSceneNotified) {
        onSceneChangedRef.current?.();
        pendingTransformSceneNotified = true;
      }
      syncSelectedTransformPreview(object);
    }

    function commitSelectedTransformChange() {
      const object = pendingTransformCommitObject;
      if (!object) return false;

      pendingTransformCommitObject = null;
      pendingTransformSceneNotified = false;
      syncSceneState(object, { changedObjects: [object] });
      markSceneChanged();
      return true;
    }

    function selectObject(object) {
      commitSelectedTransformChange();
      // 이전 선택이 피규어였다면 선택 edge를 직접 꺼준다(피규어는 editableRoots 밖이라
      // refreshCollisionState가 갱신해주지 않는다).
      const previous = selectedObjectRef.current;
      if (previous?.userData.isDecorFigure && previous !== object) {
        setFurnitureVisualState(previous, object);
      }

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

    // roomModel의 바닥 mesh만 모아 배치 클릭 raycast 대상으로 쓴다(가구가 벽/천장
    // 클릭으로 방 밖에 놓이지 않도록).
    function collectFloorMeshes() {
      const floorMeshes = [];
      roomModelRef.current?.traverse((object) => {
        if (object.isMesh && isUsdFloorMesh(object)) {
          floorMeshes.push(object);
        }
      });
      return floorMeshes;
    }

    // 클릭/터치 시작. 가구 배치 모드 중이면 바닥 클릭으로 배치를 확정하고, 아니면
    // 회전 핸들을 먼저 검사하고(controlPickTargets), 아니면 일반 가구/문/창문
    // (pickTargets)을 검사해서 선택하고 이동 드래그를 시작한다.
    function handlePointerDown(event) {
      if (event.button !== 0) return;

      if (isPersonViewRef.current) {
        personLookPointerId = event.pointerId;
        personLastPointer = { x: event.clientX, y: event.clientY };
        renderer.domElement.setPointerCapture?.(event.pointerId);
        stopSceneEvent(event);
        return;
      }

      setPointerRay(event);

      // 꾸미기 모드: 피규어만 선택/드래그할 수 있다. 피규어가 아닌 곳을 클릭하면 선택만
      // 해제하고 이벤트를 OrbitControls에 넘긴다(제한된 범위에서 시점 회전 가능).
      if (decorContext) {
        // 피규어 배치 모드: 클릭한 표면(위를 향한 면)에 대기 중인 피규어를 올려놓는다.
        if (pendingPlacementRef.current?.isFigure) {
          const support = findSupportPointOnRay(
            raycaster,
            decorContext.supportMeshes,
          );
          if (support) {
            sceneActionsRef.current?.resolvePendingFigurePlacement(
              support.point,
            );
          } else {
            setStatus("피규어를 놓을 층(선반의 위를 향한 면)을 클릭하세요.");
          }
          stopSceneEvent(event);
          return;
        }

        const figureHits = raycaster.intersectObjects(decorPickTargets(), false);
        if (figureHits.length) {
          const figureRoot = figureHits[0].object.userData.editableRoot;
          selectObject(figureRoot);
          beginFigureMoveInteraction(event, figureRoot);
          stopSceneEvent(event);
          return;
        }
        if (selectedObjectRef.current) selectObject(null);
        return;
      }

      if (pendingPlacementRef.current) {
        const floorHits = raycaster.intersectObjects(
          collectFloorMeshes(),
          true,
        );
        if (floorHits.length) {
          sceneActionsRef.current?.resolvePendingPlacement(
            floorHits[0].point,
          );
        } else {
          setStatus("가구를 놓을 바닥을 클릭하세요.");
        }
        stopSceneEvent(event);
        return;
      }

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
        hits.find((hit) =>
          canTransformObject(hit.object.userData.editableRoot),
        ) || hits[0];
      const object = editableHit.object.userData.editableRoot;
      selectObject(object);

      if (canTransformObject(object)) {
        if (
          object.userData.startsInWallCollision &&
          objectIntersectsWalls(object, activeColliders())
        ) {
          object.userData.ignoreWallConstraint = true;
        }
        beginMoveInteraction(event, object);
      }
      stopSceneEvent(event);
    }

    // pointermove 이벤트를 activeInteraction 갱신으로 라우팅한다.
    function handlePointerMove(event) {
      if (
        isPersonViewRef.current &&
        personLookPointerId === event.pointerId &&
        personLastPointer
      ) {
        const deltaX = event.clientX - personLastPointer.x;
        const deltaY = event.clientY - personLastPointer.y;
        personLastPointer = { x: event.clientX, y: event.clientY };
        personYaw -= deltaX * 0.004;
        personPitch = THREE.MathUtils.clamp(
          personPitch - deltaY * 0.003,
          -1.25,
          1.15,
        );
        camera.rotation.order = "YXZ";
        camera.rotation.set(personPitch, personYaw, 0, "YXZ");
        stopSceneEvent(event);
        return;
      }
      if (
        !activeInteraction ||
        event.pointerId !== activeInteraction.pointerId
      ) {
        return;
      }

      updateActiveInteraction(event);
      stopSceneEvent(event);
    }

    // pointerup/pointercancel 이벤트를 드래그 종료로 라우팅한다.
    function handlePointerEnd(event) {
      if (isPersonViewRef.current && personLookPointerId === event.pointerId) {
        personLookPointerId = null;
        personLastPointer = null;
        renderer.domElement.releasePointerCapture?.(event.pointerId);
        stopSceneEvent(event);
        return;
      }
      if (
        !activeInteraction ||
        event.pointerId !== activeInteraction.pointerId
      ) {
        return;
      }

      endActiveInteraction(event);
      stopSceneEvent(event);
    }

    // capture 단계(true)로 등록해서 OrbitControls보다 먼저 이벤트를 가로챌 수 있게 한다.
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

    function handlePersonKeyDown(event) {
      if (event.ctrlKey || event.metaKey) {
        if (event.code === "KeyZ") {
          event.preventDefault();
          if (event.shiftKey) redo();
          else undo();
          return;
        }
        if (event.code === "KeyY") {
          event.preventDefault();
          redo();
          return;
        }
      }
      if (!isPersonViewRef.current) return;
      const allowed = new Set([
        "KeyW",
        "KeyA",
        "KeyS",
        "KeyD",
        "ArrowUp",
        "ArrowDown",
        "ArrowLeft",
        "ArrowRight",
        "ShiftLeft",
        "ShiftRight",
      ]);
      if (!allowed.has(event.code)) return;
      event.preventDefault();
      personKeys.add(event.code);
    }

    function handlePersonKeyUp(event) {
      personKeys.delete(event.code);
    }

    window.addEventListener("keydown", handlePersonKeyDown);
    window.addEventListener("keyup", handlePersonKeyUp);

    // 여기서부터 방 모델/metadata를 실제로 로드해서 씬을 채우는 비동기 파이프라인이 시작된다.
    // roomScene(API 응답)이 있으면 그 안의 base64 모델/metadata를 우선 쓰고, 없으면
    // scene config에 설정된 기본 URL로 fallback한다.
    // 1) USD 방 모델 + metadata를 동시에 로드 → 2) 가구 카탈로그가 필요로 하는 모델
    // 템플릿들도 로드 → 3) 아래 async 콜백에서 실제로 씬을 채운다(방 모델 배치, 벽
    // 콜라이더 생성, 가구/문/창문 복원, 이벤트 핸들러가 참조할 sceneActionsRef 조립).
    Promise.all([loadUsdRoomModel(roomModelUrl), metadataPromise])
      .then(([model, metadata]) =>
        Promise.all([
          model,
          loadModelTemplates(modelCategoriesFromMetadata(metadata)),
          metadata,
        ]),
      )
      .then(async ([model, modelTemplates, metadata]) => {
        if (!isMounted) {
          if (model) disposeScene(model);
          return;
        }

        // 저장된 _spatiumRoom(이전 편집 결과)이 있으면 원본 USD 모델보다 우선한다 —
        // 그래야 이전에 편집한 벽/문/창문 상태(벽으로 메운 것 등)가 그대로 복원된다.
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
        const roomMeasurements = calculateRoomMeasurements(roomModel);
        addRoomMeasurements(roomMeasurements);
        // 방 본체에서 멀리 떨어진 오염 mesh(스캔 아티팩트, 과거 저장 버그로 남은 벽 메움
        // 등)를 숨긴다. 메인 바닥 폴리곤 기준 경계에 2m 여유를 둔 박스와 전혀 겹치지
        // 않는 mesh만 대상이라 정상적인 벽/천장/단차 바닥은 건드리지 않는다.
        const saneRoomBounds =
          framingBoundsFromMeasurements(roomMeasurements)?.expandByScalar(2) ||
          null;
        const hiddenRoomMeshes = hideOutlierRoomMeshes(
          roomModel,
          saneRoomBounds,
        );
        if (hiddenRoomMeshes.length) {
          console.warn(
            "[roomSceneEditor] Hid room meshes far outside the room body:",
            hiddenRoomMeshes,
          );
        }
        // 방이 월드 좌표축에서 얼마나 돌아가 있는지 추정해둔다 — 회전 슬라이더/표시 각도를
        // "방 기준 상대 각도"로 보여주기 위함(estimateRoomYawOffsetDegrees 참고). Skyview
        // 카메라도 이 값을 참고해서 화면상 방이 똑바로(축에 맞게) 보이도록 돌린다.
        roomYawOffsetDegrees = estimateRoomYawOffsetDegrees(
          roomMeasurements?.outlineSegments,
        );
        if (viewControllerRef.current) {
          viewControllerRef.current.roomYawOffsetDegrees = roomYawOffsetDegrees;
        }
        const roomBoundsBox = new THREE.Box3().setFromObject(roomModel);
        personBounds = roomBoundsBox.clone();
        const roomCenter = roomBoundsBox.getCenter(new THREE.Vector3());
        // roomMeasurements.center.y는 "가장 넓은 바닥 면적 그룹"의 높이라서, 방 모델에
        // 섞여 들어간 작은 오염 mesh 하나가 bounding box 전체를 끌어내리는 것에 영향받지
        // 않는다. roomMeasurements가 없을 때만(빈 방 등) bounding box 최저점으로 대체한다.
        const measuredFloorY = roomMeasurements?.center?.y;
        const roomFloorY = Number.isFinite(measuredFloorY)
          ? measuredFloorY
          : roomBoundsBox.isEmpty()
            ? 0
            : roomBoundsBox.min.y;
        floorY = estimateFloorY(metadata.objects, roomFloorY);
        ceilingY = roomBoundsBox.isEmpty() ? floorY : roomBoundsBox.max.y;
        wallColliders.push(...createWallColliders(roomModel));
        invalidateActiveColliders();
        applyRoomWallColor(wallColliders, wallColorRef.current);
        // 이전에 저장된 바닥 색상이 있으면(부모의 floorColor prop보다 우선) 그걸 복원한다.
        // 부모는 마운트 시점에 이 값을 알 수 없으므로(useState(null)로 시작), 로드가 끝난
        // 뒤 onFloorColorLoaded로 알려줘서 상위 상태와 UI를 동기화한다.
        const persistedFloorColor = metadata._spatiumFloorColor || null;
        floorColorRef.current = persistedFloorColor;
        applyRoomFloorColor(roomModel, persistedFloorColor);
        onFloorColorLoadedRef.current?.(persistedFloorColor);
        if (wallConfigBoolean("showColliderDebug")) {
          referenceLayer.add(createWallColliderVisuals(wallColliders));
        }

        const modelTemplatePromises = new Map();

        // 아이템 고유 모델(modelUrl/path)이 있으면 그걸 로드하고(동일 URL은 캐시해서
        // 한 번만 로드), 없으면 category 기본 템플릿(modelTemplates)을 쓴다.
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

          const modelTemplate = findModelTemplate(
            modelTemplates,
            item.category,
          );
          return Promise.resolve(modelTemplate?.gltf.scene || null);
        }

        // 모델 템플릿이 있으면 GLB 기반 가구를, 없으면 단색 박스 fallback 가구를 만든다.
        async function createFurnitureFromItem(item, index) {
          const modelTemplate = await loadModelTemplateForItem(item);
          return modelTemplate
            ? createEditableFurnitureModel(modelTemplate, item, index)
            : createEditableFurniture(item, index);
        }

        // 문/창문 reference 오브젝트를 만든다. 전용 모델이 없으면 색상 박스로 fallback한다.
        async function createReferenceFromItem(item, index, sourceType) {
          const referenceItem = { ...item, category: sourceType };
          const modelTemplate =
            (await loadModelTemplateForItem(referenceItem)) ||
            createFallbackReferenceTemplate(sourceType);

          return sourceType === "door"
            ? createDoorModel(
                modelTemplate,
                referenceItem,
                index,
                wallColliders,
              )
            : createWindowModel(
                modelTemplate,
                referenceItem,
                index,
                wallColliders,
              );
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

        // 저장된 transform이 오염돼 방 밖 멀리 놓인 가구를 방 안쪽으로 되돌린다 —
        // 이런 가구가 씬 bounding box를 부풀려 카메라 프레이밍까지 망가뜨린다.
        const recoveredFurniture = recoverOutOfRoomFurniture(
          editableRoots,
          roomMeasurements,
          floorY,
        );
        if (recoveredFurniture.length) {
          console.warn(
            "[roomSceneEditor] Recovered furniture with corrupted saved positions:",
            recoveredFurniture.map((root) => root.name),
          );
        }

        // 저장된 피규어(decorations)를 복원해서 각 가구 root의 자식으로 다시 부착한다.
        // transform이 부모 로컬 기준으로 저장돼 있으므로 그대로 적용하면 된다.
        await Promise.all(
          furnitureItems.map(async (furniture, index) => {
            const decorations = (metadata.objects || [])[index]?.decorations;
            if (!Array.isArray(decorations) || !decorations.length) return;

            const figures = await Promise.all(
              decorations.map(async (decorationItem, figureIndex) => {
                const modelTemplate = await loadModelTemplateForItem(
                  decorationItem,
                ).catch(() => null);
                return createDecorFigure(
                  modelTemplate,
                  decorationItem,
                  figureIndex,
                );
              }),
            );

            if (!isMounted) {
              figures.forEach((figure) => disposeScene(figure.root));
              return;
            }

            figures.forEach((figure) =>
              attachFigureToTarget(furniture.root, figure),
            );
          }),
        );

        nextObjectIndex = (metadata.objects || []).length;

        // 새로 만든 가구를 씬에 추가하고, 벽/문/창문과 안 겹치는 위치로 보정한 뒤 선택한다.
        function addFurnitureToScene(
          furniture,
          insertAt = editableRoots.length,
        ) {
          furnitureLayer.add(furniture.root);
          editableRoots.splice(insertAt, 0, furniture.root);
          pickTargets.push(...furniture.pickTargets);
          initializeWallConstraints([furniture.root], activeColliders());
          selectObject(furniture.root);
        }

        // 가구를 씬/목록/pickTargets에서 제거하고 GPU 리소스를 정리한다.
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

        // 새 문/창문 reference를 씬에 추가한다 (가구와 달리 벽 제약 초기화는 하지 않음).
        function addReferenceToScene(
          reference,
          insertAt = referenceRoots.length,
        ) {
          referenceLayer.add(reference.root);
          referenceRoots.splice(insertAt, 0, reference.root);
          pickTargets.push(...reference.pickTargets);
          invalidateActiveColliders();
          selectObject(reference.root);
        }

        // removeEditableObject와 동일한 정리 작업을 referenceRoots 목록에 대해 수행한다.
        function removeReferenceObject(object) {
          const objectIndex = referenceRoots.indexOf(object);
          if (objectIndex >= 0) {
            referenceRoots.splice(objectIndex, 1);
            invalidateActiveColliders();
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

        // React state 업데이트 타이밍과 무관하게 현재 Three.js 씬을 즉시 snapshot으로
        // 만든다. Undo/Redo와 서버 저장이 같은 직렬화 경로를 사용한다.
        function captureCurrentSnapshot() {
          const currentItems = [...editableRoots, ...referenceRoots].map(
            objectToEditableJson,
          );
          return createReplayableMetadataJson(
            sourceMetadataRef.current,
            currentItems,
            roomModelRef.current,
            floorColorRef.current,
            { roomModelJson: getRoomModelJson() },
          );
        }

        // Undo/Redo용 snapshot은 정적인 방 geometry를 직접 포함하지 않고, 바뀐
        // 방 상태의 JSON을 바깥 history cache에 등록할 수 있도록 별도로 반환한다.
        function captureHistorySnapshot() {
          const currentItems = [...editableRoots, ...referenceRoots].map(
            objectToEditableJson,
          );
          return {
            snapshot: createReplayableMetadataJson(
              sourceMetadataRef.current,
              currentItems,
              roomModelRef.current,
              floorColorRef.current,
              { includeRoomModel: false },
            ),
            roomJson: getRoomModelJson(),
          };
        }

        function applySnapshotDiff(targetSnapshot, previousSnapshot) {
          const targetItems =
            targetSnapshot?._spatiumExport?.editedItems || [];
          const previousItems =
            previousSnapshot?._spatiumExport?.editedItems || [];
          if (!targetItems.length || targetItems.length !== previousItems.length) {
            return false;
          }

          // 객체 개수·모델·치수·decor 구성이 달라졌다면 기존 노드를 재사용할 수
          // 없으므로 전체 metadata 복원 경로를 사용한다.
          const structuralPart = (item) => ({
            id: item.id,
            sourceType: item.sourceType,
            index: item.index,
            category: item.category,
            path: item.path,
            modelUrl: item.modelUrl,
            dimensions: item.dimensions,
            decorations: item.decorations || [],
          });
          const targetById = new Map(targetItems.map((item) => [item.id, item]));
          const previousById = new Map(
            previousItems.map((item) => [item.id, item]),
          );
          if (targetById.size !== previousById.size) return false;
          const changedIds = [];

          for (const [id, targetItem] of targetById) {
            const previousItem = previousById.get(id);
            if (!previousItem) return false;
            if (
              JSON.stringify(structuralPart(targetItem)) !==
              JSON.stringify(structuralPart(previousItem))
            ) {
              return false;
            }
            if (!targetItem.transform?.columns) return false;
            if (
              JSON.stringify(targetItem.transform.columns) !==
              JSON.stringify(previousItem.transform?.columns)
            ) {
              changedIds.push(id);
            }
          }

          // history snapshot은 방 geometry 자체가 아니라 cache 참조를 비교한다.
          // 기존 full snapshot과의 호환을 위해 실제 JSON 비교도 fallback으로 둔다.
          if (
            targetSnapshot._spatiumRoomRef !== undefined ||
            previousSnapshot._spatiumRoomRef !== undefined
          ) {
            if (
              targetSnapshot._spatiumRoomRef !==
              previousSnapshot._spatiumRoomRef
            ) {
              return false;
            }
          } else if (
            JSON.stringify(targetSnapshot._spatiumRoom || null) !==
            JSON.stringify(previousSnapshot._spatiumRoom || null)
          ) {
            return false;
          }
          if (
            targetSnapshot._spatiumFloorColor !==
            previousSnapshot._spatiumFloorColor
          ) {
            return false;
          }

          const sceneObjects = new Map(
            [...editableRoots, ...referenceRoots].map((object) => [
              `${object.userData.sourceType}-${object.userData.sourceIndex}`,
              object,
            ]),
          );
          if (sceneObjects.size !== targetById.size) return false;

          const changedObjects = [];
          for (const id of changedIds) {
            const targetItem = targetById.get(id);
            const object = sceneObjects.get(id);
            if (!object) return false;
            matrixFromColumns(targetItem.transform.columns).decompose(
              object.position,
              object.quaternion,
              object.scale,
            );
            object.updateWorldMatrix(true, false);
            rememberValidTransform(object);
            changedObjects.push(object);
          }

          syncSceneState(selectedObjectRef.current, { changedObjects });
          return true;
        }

        // 이 훅 바깥쪽 wrapper 함수들(addFurniture, rotateSelectedObject 등)이 호출하는
        // 실제 구현체 모음. 씬이 준비된 이후에만 존재하므로, wrapper들은 항상 null 체크한다.
        sceneActionsRef.current = {
          captureSnapshot: captureCurrentSnapshot,
          captureHistorySnapshot,
          applySnapshotDiff,
          commitSelectedTransformChange,
          setPersonView: (enabled) => {
            applyPersonView(Boolean(enabled));
          },
          // 카탈로그에서 새 가구를 추가하는 "바닥 클릭 배치" 모드를 시작한다. 문/창문
          // 카테고리는 거부한다(교체로만 가능). 실제 배치는 resolvePendingPlacement에서
          // 이뤄진다.
          beginPlaceFurniture: (catalogItem, customDimensions) => {
            if (!catalogItem) return false;
            if (REFERENCE_CATEGORIES.has(catalogItem.category)) {
              setStatus("");
              setError(
                "문과 창문은 기존 문/창문을 선택한 후 교체로만 적용하세요.",
              );
              return false;
            }

            pendingPlacementRef.current = { catalogItem, customDimensions };
            setIsPlacingFurniture(true);
            setError("");
            setStatus("가구를 놓을 위치를 바닥에서 클릭하세요.");
            renderer.domElement.style.cursor = "crosshair";
            return true;
          },
          // 진행 중인 배치 모드를 취소한다.
          cancelPlaceFurniture: () => {
            if (!pendingPlacementRef.current) return false;
            pendingPlacementRef.current = null;
            setIsPlacingFurniture(false);
            setStatus("");
            renderer.domElement.style.cursor = "default";
            return true;
          },
          // 배치 모드 중 바닥 클릭 지점(point, world space)에 대기 중이던 가구를 만든다.
          resolvePendingPlacement: async (point) => {
            const pending = pendingPlacementRef.current;
            if (!pending) return false;

            pendingPlacementRef.current = null;
            setIsPlacingFurniture(false);
            renderer.domElement.style.cursor = "default";
            setError("");
            setStatus(`Adding ${pending.catalogItem.name || "furniture"}...`);

            try {
              const effectiveCatalogItem = pending.customDimensions
                ? { ...pending.catalogItem, dimensions: pending.customDimensions }
                : pending.catalogItem;
              const dimensions = normalizedDimensions(
                effectiveCatalogItem.dimensions,
              );
              const position = new THREE.Vector3(
                point.x,
                floorY + dimensions.y / 2,
                point.z,
              );
              // 새 가구는 "방 기준 회전 0도"(roomYawOffsetDegrees, 즉 방 벽에 맞춰
              // 정렬된 각도)로 놓는다. world quaternion identity를 그대로 쓰면 방이
              // 축에서 틀어져 있을 때 회전값이 0이 아닌 값으로 표시된다.
              const quaternion = new THREE.Quaternion().setFromAxisAngle(
                upAxis,
                THREE.MathUtils.degToRad(roomYawOffsetDegrees),
              );
              const item = createFurnitureItemFromCatalog(
                effectiveCatalogItem,
                position,
                quaternion,
              );
              const objectIndex = nextObjectIndex;
              nextObjectIndex += 1;
              const furniture = await createFurnitureFromItem(
                item,
                objectIndex,
              );

              if (!isMounted) {
                disposeScene(furniture.root);
                return false;
              }

              addFurnitureToScene(furniture);
              markSceneChanged();
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
          // 선택된 가구/문/창문을 다른 카탈로그 모델로 교체한다. 가구<->문/창문 간
          // 교체는 막는다(같은 계열끼리만 교체 가능).
          replaceSelectedObject: async (catalogItem) => {
            const object = selectedObjectRef.current;
            if (!catalogItem || !isReplaceableObject(object)) return false;

            const sourceType = object.userData.sourceType;
            const isOpening = sourceType === "opening";
            if (
              sourceType === "object" &&
              REFERENCE_CATEGORIES.has(catalogItem.category)
            ) {
              setStatus("");
              setError("문/창문 모델은 기존 문/창문을 선택한 후 교체하세요.");
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
            if (isOpening && !REFERENCE_CATEGORIES.has(catalogItem.category)) {
              setStatus("");
              setError("개구부에는 문/창문 모델만 채울 수 있습니다.");
              return false;
            }

            setError("");
            setStatus(`Replacing with ${catalogItem.name || "furniture"}...`);

            try {
              const isReferenceReplacement =
                REFERENCE_CATEGORIES.has(sourceType) || isOpening;
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
                // 교체로 들어온 문/창문도 초기 로딩 때와 동일하게 roomFacingNormal을
                // 설정해야 카메라 각도에 따라 벽과 함께 흐려지는 처리가 적용된다.
                initializeReferenceFacingNormal(nextObject.root, roomCenter);
                if (showReferenceLabels) {
                  const debugLabel = createReferenceDebugLabel();
                  const labelHeight =
                    nextObject.root.userData.localObb?.halfSize?.y ?? 1;
                  debugLabel.position.set(0, labelHeight + 0.2, 0);
                  nextObject.root.userData.debugLabel = debugLabel;
                  nextObject.root.add(debugLabel);
                }

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
              markSceneChanged();
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
          // 90도 회전 버튼. 벽과 충돌하면 즉시 되돌린다.
          rotateSelectedObject: () => {
            const object = selectedObjectRef.current;
            if (!isReplaceableObject(object)) return false;

            const previousQuaternion = object.quaternion.clone();
            object.quaternion.premultiply(
              new THREE.Quaternion().setFromAxisAngle(upAxis, Math.PI / 2),
            );
            object.updateWorldMatrix(true, false);
            if (hasWallCollision(object, activeColliders())) {
              object.quaternion.copy(previousQuaternion);
              object.updateWorldMatrix(true, false);
              syncSceneState(object);
              return false;
            }
            rememberValidTransform(object);
            syncSceneState(object);
            markSceneChanged();
            return true;
          },
          // 회전 슬라이더로 각도를 직접 지정한다. 슬라이더 값은 "방 기준 상대 각도"이므로
          // roomYawOffsetRef를 더해 월드 절대 각도로 바꿔서 적용한다. 마찬가지로 벽 충돌 시
          // 되돌린다.
          // 회전 슬라이더로 각도를 직접 지정한다. 마찬가지로 벽 충돌 시 되돌린다.
          setSelectedRotationDegrees: (degrees) => {
            const object = selectedObjectRef.current;
            if (!isReplaceableObject(object)) return false;

            const roomRelativeDegrees = Number(degrees) || 0;
            const worldDegrees = roomRelativeDegrees + roomYawOffsetDegrees;
            const previousQuaternion = object.quaternion.clone();
            object.quaternion.setFromAxisAngle(
              upAxis,
              THREE.MathUtils.degToRad(worldDegrees),
            );
            object.updateWorldMatrix(true, false);
            if (hasWallCollision(object, activeColliders())) {
              object.quaternion.copy(previousQuaternion);
              object.updateWorldMatrix(true, false);
              syncSelectedTransformPreview(object);
              return false;
            }
            rememberValidTransform(object);
            markTransformPreview(object);
            return true;
          },
          // 높이 슬라이더로 바닥에서 띄운 높이를 직접 지정한다(0~elevationBoundsForObject
          // 범위로 clamp). 벽 충돌 시 되돌린다.
          setSelectedElevationCm: (elevationCm) => {
            const object = selectedObjectRef.current;
            if (!canTransformObject(object)) return false;

            const bounds = elevationBoundsForObject(object);
            const clampedCm = THREE.MathUtils.clamp(
              Number(elevationCm) || 0,
              0,
              bounds.maxCm,
            );
            const halfHeight = object.userData.localObb?.halfSize?.y ?? 0;
            const previousY = object.position.y;
            object.position.y = floorY + halfHeight + clampedCm / 100;
            object.updateWorldMatrix(true, false);
            if (hasWallCollision(object, activeColliders())) {
              object.position.y = previousY;
              object.updateWorldMatrix(true, false);
              syncSelectedTransformPreview(object);
              return false;
            }
            rememberValidTransform(object);
            markTransformPreview(object);
            return true;
          },
          // 배치 후 일반 가구의 최대 변(cm)을 균일하게 조절한다. 바닥/선반에 놓인
          // 상태를 유지하기 위해 하단 높이를 먼저 기억하고 새 스케일에 맞춰 Y를 보정한다.
          setSelectedSizeCm: (sizeCm) => {
            const object = selectedObjectRef.current;
            if (!canTransformObject(object) || object.userData.isDecorFigure) {
              return false;
            }

            const halfSize = object.userData.localObb?.halfSize;
            if (!halfSize) return false;
            const currentSize = halfSize
              .clone()
              .multiplyScalar(2)
              .multiply(object.scale);
            const currentMax = Math.max(
              currentSize.x,
              currentSize.y,
              currentSize.z,
            );
            if (!Number.isFinite(currentMax) || currentMax <= 0) return false;

            const clampedCm = THREE.MathUtils.clamp(
              Number(sizeCm) || 0,
              10,
              500,
            );
            const previousScale = object.scale.clone();
            const previousPosition = object.position.clone();
            const bottomY =
              object.position.y - halfSize.y * object.scale.y;
            const ratio = clampedCm / 100 / currentMax;
            object.scale.multiplyScalar(ratio);
            object.position.y = bottomY + halfSize.y * object.scale.y;
            object.updateWorldMatrix(true, false);

            if (hasWallCollision(object, activeColliders())) {
              object.scale.copy(previousScale);
              object.position.copy(previousPosition);
              object.updateWorldMatrix(true, false);
              syncSelectedTransformPreview(object);
              return false;
            }

            rememberValidTransform(object);
            markTransformPreview(object);
            return true;
          },
          // 선택된 일반 가구를 삭제한다. 문/창문은 이 액션 대상이 아니다(deleteSelectedReference).
          deleteSelectedObject: () => {
            const object = selectedObjectRef.current;

            // 꾸미기 모드의 피규어 삭제 — 서랍장에서 떼어내고 정리한다.
            if (object?.userData.sourceType === "figure") {
              detachFigureFromTarget(object);
              selectedObjectRef.current = null;
              setReplaceMode(false);
              syncSceneState(null);
              markSceneChanged();
              setStatus("피규어를 삭제했습니다.");
              window.setTimeout(() => setStatus(""), 900);
              return true;
            }

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
            markSceneChanged();
            setStatus("Deleted furniture.");
            window.setTimeout(() => setStatus(""), 900);
            return true;
          },
          // 선택된 문/창문을 삭제한다. fillWithWall이면 그 자리를 벽으로 메운 뒤(콜라이더
          // 재생성 + 기존 가구 재보정까지) reference를 제거한다. 아니면 문/창문 모델만
          // 지우고, 나중에 다시 채워 넣을 수 있도록 그 자리에 선택 가능한 개구부 마커를
          // 남긴다(카탈로그에서 문/창문을 골라 "교체"하면 그 마커가 채워진다).
          deleteSelectedReference: (fillWithWall) => {
            const object = selectedObjectRef.current;
            if (!object || !REFERENCE_CATEGORIES.has(object.userData.sourceType)) {
              return false;
            }

            if (fillWithWall) {
              const infill = createWallInfillMesh(
                object,
                wallColliders,
                object.userData.sourceIndex ?? 0,
              );
              roomModel.add(infill);
              invalidateRoomModelJsonCache();
              wallColliders.length = 0;
              wallColliders.push(...createWallColliders(roomModel));
              invalidateActiveColliders();
              applyRoomWallColor(wallColliders, wallColorRef.current);
              initializeWallConstraints(editableRoots, activeColliders());
              removeReferenceObject(object);
              selectedObjectRef.current = null;
              setReplaceMode(false);
              syncSceneState(null);
            } else {
              const openingHalfSize = object.userData.localObb?.halfSize;
              const openingDimensions = openingHalfSize
                ? {
                    x: openingHalfSize.x * 2,
                    y: openingHalfSize.y * 2,
                    z: openingHalfSize.z * 2,
                  }
                : object.userData.roomItem?.dimensions;
              const openingItem = {
                name:
                  object.userData.sourceType === "door"
                    ? "문 개구부"
                    : "창문 개구부",
                category: "opening",
                dimensions: openingDimensions,
                transform: roundedTransform(
                  object.position,
                  object.quaternion,
                  object.scale,
                ),
              };
              const insertAt = removeReferenceObject(object);
              const openingIndex = referenceRoots.filter(
                (root) => root.userData.sourceType === "opening",
              ).length;
              const opening = createOpeningMarker(openingItem, openingIndex);

              initializeReferenceFacingNormal(opening.root, roomCenter);
              setReplaceMode(false);
              addReferenceToScene(
                opening,
                insertAt >= 0 ? insertAt : referenceRoots.length,
              );
            }

            markSceneChanged();
            setStatus(fillWithWall ? "벽으로 메웠습니다." : "개구부로 남겼습니다.");
            window.setTimeout(() => setStatus(""), 900);
            return true;
          },
          // 선택된 서랍장에 대해 꾸미기 모드를 시작한다. 현재 시점/컨트롤 제한을 저장해두고
          // 서랍장 정면 시점으로 부드럽게 전환한 뒤, orbit 범위를 정면 주변으로 제한한다.
          enterDecorMode: () => {
            const target = selectedObjectRef.current;
            if (decorContext || !canDecorateObject(target)) return false;
            if (viewControllerRef.current?.isInSkyview) {
              setError("Skyview를 끈 뒤 서랍장 꾸미기를 시작하세요.");
              return false;
            }

            sceneActionsRef.current?.cancelPlaceFurniture?.();

            const view = computeDecorView(target, camera, roomCenter);
            decorContext = {
              target,
              supportMeshes: collectSupportMeshes(target),
              savedView: captureCameraView(camera, controls),
              savedLimits: captureControlLimits(controls),
            };

            startCameraTransition(
              viewControllerRef.current,
              view,
              Math.max(controls.maxDistance, view.distance * 1.8),
              () => {
                // 전환이 끝난 뒤에만 컨트롤 제한을 적용한다 — 전환 도중 OrbitControls
                // 클램핑이 애니메이션과 충돌하지 않게. 그 사이 모드가 종료됐으면 건너뛴다.
                if (decorContext?.target === target) {
                  applyDecorControlLimits(controls, view);
                }
              },
            );

            selectObject(null);
            setDecorModeState({
              active: true,
              targetName:
                target.userData.roomItem?.name ||
                target.userData.roomItem?.category ||
                "서랍장",
            });
            setError("");
            setStatus("왼쪽 목록에서 피규어를 클릭해 서랍장 위에 올려놓으세요.");
            return true;
          },
          // 꾸미기 모드를 종료하고 저장해둔 원래 시점/컨트롤 제한으로 복귀한다.
          exitDecorMode: () => {
            if (!decorContext) return false;

            // 진행 중인 피규어 배치 모드가 있으면 함께 취소한다.
            if (pendingPlacementRef.current?.isFigure) {
              pendingPlacementRef.current = null;
              setIsPlacingFurniture(false);
              renderer.domElement.style.cursor = "default";
            }

            const { target, savedView, savedLimits } = decorContext;
            decorContext = null;

            startCameraTransition(
              viewControllerRef.current,
              savedView,
              savedLimits.maxDistance,
              () => restoreControlLimits(controls, savedLimits),
            );

            setDecorModeState({ active: false, targetName: "" });
            setStatus("");
            selectObject(target);
            return true;
          },
          isDecorModeActive: () => Boolean(decorContext),
          // 크기 슬라이더로 피규어의 최대 변 길이(cm)를 지정한다. 균일 스케일이며,
          // 바닥면이 현재 놓인 표면에 그대로 붙어 있도록 Y를 함께 보정한다.
          setSelectedFigureSizeCm: (sizeCm) => {
            const object = selectedObjectRef.current;
            if (object?.userData.sourceType !== "figure") return false;

            const halfSize = object.userData.localObb?.halfSize;
            const baseMaxDimension = halfSize
              ? Math.max(halfSize.x, halfSize.y, halfSize.z) * 2
              : 0;
            if (baseMaxDimension <= 0) return false;

            const clampedCm = THREE.MathUtils.clamp(
              Number(sizeCm) || 0,
              FIGURE_MIN_SIZE_CM,
              FIGURE_MAX_SIZE_CM,
            );
            // 스케일 변경 전의 바닥 높이(부모 로컬)를 기억해뒀다가, 새 스케일의
            // 바닥 오프셋(figureBottomOffset은 scale 반영)으로 되돌려 붙인다.
            const supportY = object.position.y + figureBottomOffset(object);
            object.scale.setScalar(clampedCm / 100 / baseMaxDimension);
            object.position.y = supportY - figureBottomOffset(object);
            object.updateWorldMatrix(true, false);
            rememberValidTransform(object);
            markTransformPreview(object);
            return true;
          },
          // 카탈로그에서 피규어를 고르면 "선반 클릭 배치" 모드를 시작한다. 실제 배치는
          // 사용자가 서랍장의 위를 향한 면(상판/선반 바닥)을 클릭한 시점에 이뤄진다
          // (resolvePendingFigurePlacement) — 클릭한 층에 그대로 놓인다.
          addFigureFromCatalog: (catalogItem) => {
            if (!decorContext || !catalogItem) return false;

            pendingPlacementRef.current = { catalogItem, isFigure: true };
            setIsPlacingFurniture(true);
            setError("");
            setStatus("피규어를 놓을 층(선반)을 클릭하세요.");
            renderer.domElement.style.cursor = "crosshair";
            return true;
          },
          // 피규어 배치 모드 중 사용자가 클릭한 표면 지점(point, world space)에
          // 대기 중이던 피규어를 만들어 올려놓는다.
          resolvePendingFigurePlacement: async (point) => {
            const pending = pendingPlacementRef.current;
            if (!pending?.isFigure || !decorContext) return false;

            const target = decorContext.target;
            const catalogItem = pending.catalogItem;
            pendingPlacementRef.current = null;
            setIsPlacingFurniture(false);
            renderer.domElement.style.cursor = "default";
            setError("");
            setStatus(`${catalogItem.name || "피규어"} 올리는 중...`);

            try {
              const dimensions = figureDimensionsFromCatalog(
                catalogItem.dimensions,
              );
              const item = {
                catalogId: catalogItem.id,
                name: catalogItem.name,
                category: catalogItem.category || "figure",
                path: catalogItem.path || catalogItem.modelUrl,
                modelUrl: catalogItem.modelUrl,
                dimensions,
                transform: roundedTransform(new THREE.Vector3()),
              };
              const modelTemplate = await loadModelTemplateForItem(item).catch(
                () => null,
              );

              // 모델 로딩 중 모드가 종료/전환됐으면 중단한다.
              if (!isMounted || decorContext?.target !== target) return false;

              const figureIndex = (target.userData.decorRoots || []).length;
              const figure = createDecorFigure(
                modelTemplate,
                item,
                figureIndex,
              );
              attachFigureToTarget(target, figure);
              placeFigureAtSupportPoint(figure.root, point);
              rememberValidTransform(figure.root);

              selectObject(figure.root);
              markSceneChanged();
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
          // 선택된 피규어를 다른 카탈로그 모델로 교체한다. 기존 피규어의 바닥 위치/회전을
          // 유지한다.
          replaceSelectedFigure: async (catalogItem) => {
            const figureRoot = selectedObjectRef.current;
            if (
              !decorContext ||
              !catalogItem ||
              figureRoot?.userData.sourceType !== "figure"
            ) {
              return false;
            }

            const target = decorContext.target;
            setError("");
            setStatus(`${catalogItem.name || "피규어"}(으)로 교체 중...`);

            try {
              const dimensions = figureDimensionsFromCatalog(
                catalogItem.dimensions,
              );
              const bottomY =
                figureRoot.position.y + figureBottomOffset(figureRoot);
              const item = {
                catalogId: catalogItem.id,
                name: catalogItem.name,
                category: catalogItem.category || "figure",
                path: catalogItem.path || catalogItem.modelUrl,
                modelUrl: catalogItem.modelUrl,
                dimensions,
                transform: roundedTransform(
                  figureRoot.position.clone(),
                  figureRoot.quaternion.clone(),
                ),
              };
              const modelTemplate = await loadModelTemplateForItem(item).catch(
                () => null,
              );

              if (!isMounted || decorContext?.target !== target) return false;

              const figure = createDecorFigure(
                modelTemplate,
                item,
                figureRoot.userData.sourceIndex,
              );
              detachFigureFromTarget(figureRoot);
              attachFigureToTarget(target, figure);
              // 새 피규어의 바닥면이 기존 피규어가 놓여 있던 표면 높이에 오도록 보정한다.
              figure.root.position.y = bottomY - figureBottomOffset(figure.root);
              figure.root.updateWorldMatrix(true, false);
              rememberValidTransform(figure.root);

              selectObject(figure.root);
              markSceneChanged();
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
          setWallColor: (color) => {
            invalidateRoomModelJsonCache();
            applyRoomWallColor(wallColliders, color);
            needsRender = true;
          },
          setFloorColor: (color) => {
            applyRoomFloorColor(roomModel, color);
            needsRender = true;
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
        // 개구부(문/창문을 "개구부로 삭제"해서 남은 빈 구멍) 마커. GLB 로딩이 필요 없어
        // Promise.all 없이 바로 만든다.
        const openingItems = (metadata.openings || []).map((item, index) =>
          createOpeningMarker(item, index),
        );

        if (!isMounted) {
          [...doorItems, ...windowItems, ...openingItems].forEach((item) =>
            disposeScene(item.root),
          );
          return;
        }

        // 문/창문/개구부를 씬에 등록하고, 카메라 각도에 따라 흐려지는 처리에 필요한
        // roomFacingNormal을 계산해둔다. 저장된 transform이 오염돼 방 밖 멀리 놓인
        // 것들은 씬에 넣지 않는다(문/창문은 벽에 붙어 있어야 의미가 있어서, 가구처럼
        // 방 안으로 옮겨봐야 쓸모가 없다).
        const skippedReferences = [];
        [...doorItems, ...windowItems, ...openingItems].forEach((item) => {
          if (saneRoomBounds && !saneRoomBounds.containsPoint(item.root.position)) {
            skippedReferences.push(item.root.name || "reference");
            disposeScene(item.root);
            return;
          }
          initializeReferenceFacingNormal(item.root, roomCenter);
          if (showReferenceLabels) {
            const debugLabel = createReferenceDebugLabel();
            const labelHeight = item.root.userData.localObb?.halfSize?.y ?? 1;
            debugLabel.position.set(0, labelHeight + 0.2, 0);
            item.root.userData.debugLabel = debugLabel;
            item.root.add(debugLabel);
          }
          referenceLayer.add(item.root);
          referenceRoots.push(item.root);
          pickTargets.push(...item.pickTargets);
        });
        if (skippedReferences.length) {
          console.warn(
            "[roomSceneEditor] Skipped doors/windows/openings far outside the room:",
            skippedReferences,
          );
        }
        invalidateActiveColliders();

        // 문/창문까지 전부 로드된 뒤 마지막으로 한 번 더 벽 제약을 적용한다 — 이제
        // activeColliders()에 문/창문도 포함되므로, 초기 가구가 문/창문과 겹쳐 있으면
        // 이 시점에 밀려난다.
        initializeWallConstraints(editableRoots, activeColliders());

        if (editableRoots[0]) selectObject(editableRoots[0]);
        if (!editableRoots.length) syncSceneState(null);
        // 초기 프레이밍 거리보다 휠로 더 멀리 줌아웃할 수 없게 막는다.
        // 프레이밍은 raw bounding box 대신 메인 바닥 폴리곤 기준 박스를 우선 쓴다 —
        // 오염 mesh 하나가 raw 박스를 부풀리면 카메라가 수백 km 밖에 놓이기 때문.
        const framingBounds = framingBoundsFromMeasurements(roomMeasurements);
        if (framingBounds && !roomBoundsBox.isEmpty()) {
          const rawSize = roomBoundsBox.getSize(new THREE.Vector3());
          const framedSize = framingBounds.getSize(new THREE.Vector3());
          const rawMax = Math.max(rawSize.x, rawSize.y, rawSize.z);
          const framedMax = Math.max(framedSize.x, framedSize.y, framedSize.z);
          if (rawMax > framedMax * 3) {
            console.warn(
              "[roomSceneEditor] Room bounding box looks contaminated by outlier geometry.",
              { rawSize, framedSize },
            );
          }
        }
        const framedDistance = frameObject(
          camera,
          controls,
          worldGroup,
          framingBounds,
        );
        if (framedDistance) {
          controls.maxDistance = framedDistance;
        }

        // 디버그용 씬 감사 도구. 브라우저 콘솔에서 spatiumSceneAudit()을 호출하면
        // 씬의 모든 보이는 mesh 중 방 경계(메인 바닥 기준 + 3m)를 벗어난 것들을
        // 벗어난 거리 순으로 정렬해 표로 보여준다 — "방 밖/밑에 렌더링되는 무언가"가
        // 정확히 어떤 오브젝트인지 추적하기 위한 도구다.
        window.spatiumSceneAudit = () => {
          const auditBounds =
            framingBoundsFromMeasurements(roomMeasurements)?.expandByScalar(3);
          if (!auditBounds) {
            console.warn("No floor-based room bounds available for audit.");
            return [];
          }
          const rows = [];
          const meshBox = new THREE.Box3();
          worldGroup.updateWorldMatrix(true, true);
          worldGroup.traverse((object) => {
            if (!object.isMesh || !object.visible || !object.geometry) return;
            meshBox.setFromObject(object);
            if (meshBox.isEmpty()) return;
            const overflow = Math.max(
              auditBounds.min.x - meshBox.min.x,
              auditBounds.min.y - meshBox.min.y,
              auditBounds.min.z - meshBox.min.z,
              meshBox.max.x - auditBounds.max.x,
              meshBox.max.y - auditBounds.max.y,
              meshBox.max.z - auditBounds.max.z,
              0,
            );
            if (overflow <= 0) return;
            const chain = [];
            for (let node = object; node && node !== worldGroup; node = node.parent) {
              if (node.name) chain.unshift(node.name);
            }
            rows.push({
              path: chain.join(" / ") || "(unnamed)",
              overflowM: +overflow.toFixed(2),
              min: meshBox.min.toArray().map((v) => +v.toFixed(2)),
              max: meshBox.max.toArray().map((v) => +v.toFixed(2)),
            });
          });
          rows.sort((a, b) => b.overflowM - a.overflowM);
          console.table(rows);
          // 가구별 저장 상태(위치/scale/치수)도 함께 보여준다 — 오염이 transform의
          // scale에 있는지 dimensions에 있는지 구분하기 위한 표.
          console.table(
            editableRoots.map((root) => ({
              name: root.name,
              position: root.position.toArray().map((v) => +v.toFixed(2)),
              scale: root.scale.toArray().map((v) => +v.toFixed(4)),
              dims: [
                root.userData.roomItem?.dimensions?.x,
                root.userData.roomItem?.dimensions?.y,
                root.userData.roomItem?.dimensions?.z,
              ],
            })),
          );
          return rows;
        };
        if (viewControllerRef.current) {
          viewControllerRef.current.baseMaxDistance = controls.maxDistance;
          viewControllerRef.current.defaultView = captureCameraView(
            camera,
            controls,
          );
          applySkyviewMode(viewControllerRef.current, isSkyviewRef.current, {
            instant: true,
          });
          if (isPersonViewRef.current) {
            applyPersonView(true);
          }
        }

        const initialSnapshot = registerHistoryCapture(
          captureHistorySnapshot(),
        );
        if (historyApplyingRef.current) {
          historyApplyingRef.current = false;
          metadataOverrideRef.current = null;
          if (!historyRef.current.past.length) {
            historyRef.current = {
              past: [cloneSnapshot(initialSnapshot)],
              future: [],
            };
          }
        } else {
          historyRef.current = {
            past: [cloneSnapshot(initialSnapshot)],
            future: [],
          };
        }
        trimHistoryRoomCache();
        setHistoryVersion((value) => value + 1);
        // 비동기 초기 로딩(방/가구/문/창문 복원)이 이 시점 이후에 끝나므로, 렌더 루프가
        // 이미 이전 프레임들에서 needsRender를 소비해 false로 바꿔놨을 수 있다 — 로딩이
        // 끝난 씬이 실제로 화면에 그려지도록 여기서 다시 true로 세팅한다.
        needsRender = true;
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

    // 매 프레임 실행되는 렌더 루프. OrbitControls damping 갱신, 카메라를 가리는 벽/문/창문
    // 투명 처리, 카메라 각도 배지 갱신, 렌더링까지 담당한다. Skyview 전환 애니메이션이
    // 진행 중이면(updateCameraTransition이 true 반환) 그 프레임엔 일반 controls.update()를
    // 건너뛴다 — 안 그러면 OrbitControls의 내부 상태가 전환 중 직접 설정한 카메라 값과
    // 충돌한다.
    // 투명 처리, 카메라 각도 배지 갱신, 렌더링까지 담당한다.
    // 직전 프레임의 카메라 자세. 카메라가 안 움직인 프레임에는 벽/문/창문 투명 처리를
    // 통째로 건너뛰기 위한 비교 기준이다. 초기값은 실제 카메라와 절대 같을 수 없는 값으로
    // 둬서 첫 프레임엔 반드시 실행되게 한다.
    const lastCameraPosition = new THREE.Vector3(Infinity, Infinity, Infinity);
    const lastCameraQuaternion = new THREE.Quaternion();
    let lastCameraAngleText = "";

    function animate() {
      frameId = requestAnimationFrame(animate);
      const now = performance.now();
      const deltaSeconds = Math.min((now - previousAnimationTime) / 1000, 0.05);
      previousAnimationTime = now;
      const isCameraTransitioning = updateCameraTransition(
        viewControllerRef.current,
      );
      if (!isCameraTransitioning && viewControllerRef.current?.isPersonView) {
        updatePersonMovement(deltaSeconds);
      }
      if (!isCameraTransitioning && !viewControllerRef.current?.isPersonView) {
        controls.update();
      }
      // 벽 투명 처리는 카메라 시점의 함수이므로, 카메라가 움직였거나(회전/이동/전환 애니메이션)
      // 벽·문/창문 구성이 바뀐(viewFacingWallsDirty) 프레임에만 다시 계산한다.
      const cameraMoved =
        !lastCameraPosition.equals(camera.position) ||
        !lastCameraQuaternion.equals(camera.quaternion);
      if (cameraMoved || viewFacingWallsDirty) {
        lastCameraPosition.copy(camera.position);
        lastCameraQuaternion.copy(camera.quaternion);
        viewFacingWallsDirty = false;
        updateViewFacingWalls(wallColliders, camera, referenceRoots);
        if (cameraAngleBadge) {
          const nextCameraAngleText = formatCameraViewAngle(camera, controls);
          if (nextCameraAngleText !== lastCameraAngleText) {
            cameraAngleBadge.textContent = nextCameraAngleText;
            lastCameraAngleText = nextCameraAngleText;
          }
        }
      }
      // GPU를 계속 점유하지 않도록, 실제로 화면이 바뀔 때만 그린다(on-demand rendering).
      // needsRender: 가구 추가/이동/회전/삭제/교체, undo/redo, 벽/바닥 색상 변경, 창 리사이즈,
      // 초기 씬 로딩 완료 등 syncSceneState/syncDragState를 거치는 모든 조작에서 true가 된다.
      // cameraMoved: 오빗 컨트롤 드래그·줌·댐핑 관성, 1인칭 이동까지 전부 포함해 카메라
      // 위치/자세가 실제로 바뀐 프레임을 잡아낸다. isCameraTransitioning은 스카이뷰 등
      // 카메라 전환 애니메이션 중 안전장치로 둔다.
      if (needsRender || cameraMoved || isCameraTransitioning) {
        renderer.render(scene, camera);
        labelRenderer.render(scene, camera);
        needsRender = false;
      }
    }
    animate();

    // 컨테이너 크기가 바뀌면(윈도우 리사이즈 등) 카메라 종횡비와 렌더러 크기를 맞춘다.
    function resize() {
      const nextWidth = root.clientWidth || window.innerWidth;
      const nextHeight = root.clientHeight || window.innerHeight;
      camera.aspect = nextWidth / nextHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(nextWidth, nextHeight);
      labelRenderer.setSize(nextWidth, nextHeight);
      needsRender = true;
    }

    window.addEventListener("resize", resize);
    syncSelectedRef.current = () => syncSceneState(selectedObjectRef.current);

    // effect cleanup — 씬이 재생성되거나 컴포넌트가 언마운트될 때 애니메이션 루프/이벤트
    // 리스너를 정리하고 Three.js 리소스를 전부 dispose한다.
    return () => {
      isMounted = false;
      cancelAnimationFrame(frameId);
      window.removeEventListener("resize", resize);
      window.removeEventListener("keydown", handlePersonKeyDown);
      window.removeEventListener("keyup", handlePersonKeyUp);
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
      syncRoomMeasurementsRef.current = null;
      sourceMetadataRef.current = null;
      roomModelRef.current = null;
      roomMeasurementsRef.current = null;
      viewControllerRef.current = null;
      sceneActionsRef.current = null;
      pendingPlacementRef.current = null;
      setCollisionSummary({ hasCollision: false, with: [] });
      setDecorModeState({ active: false, targetName: "" });
      controls.dispose();
      // 캐시 템플릿과 공유하던 texture도 이 렌더러 세션에서는 반드시 dispose해야
      // Three.js가 등록한 texture dispose listener와 WebGLTexture가 함께 해제된다.
      disposeScene(scene, { disposeSharedTextures: true });
      renderer.dispose();
      // renderer.dispose()만으로는 브라우저가 WebGL context를 계속 보관할 수 있다.
      // 페이지 재진입 때 새 context가 누적되지 않도록 명시적으로 context를 잃게 한다.
      renderer.forceContextLoss();
      renderer.domElement.width = 1;
      renderer.domElement.height = 1;
      root.replaceChildren();
      if (roomModelObjectUrl) {
        URL.revokeObjectURL(roomModelObjectUrl);
      }
    };
  // The scene effect intentionally owns a stable imperative Three.js session;
  // refs carry the latest callbacks without recreating the scene per render.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    isSceneConfigReady,
    sceneRevision,
    isSkyviewRef,
    roomScene,
    selectedObjectRef,
    setError,
    setIsPlacingFurniture,
    setReplaceMode,
    setSelectedItem,
    setSelectedRotationDegreesState,
    setSelectedElevationCmState,
    setSelectedMaxElevationCmState,
    setSelectedSizeCmState,
    setStatus,
  ]);

  // sceneRevision 기반 재구성 중에는 GLTF를 재사용하고, 편집 페이지 자체가 닫힐 때만
  // 모듈 캐시를 비워 다른 방/사용자 모델이 탭 수명 동안 계속 누적되지 않게 한다.
  useEffect(
    () => () => {
      clearGltfModelCache();
    },
    [],
  );

  return {
    containerRef,
    error,
    selectedItem,
    selectedRotationDegrees,
    selectedElevationCm,
    selectedMaxElevationCm,
    selectedSizeCm,
    editedItems,
    isReplacingSelected,
    isPlacingFurniture,
    collisionSummary,
    canResetSelected,
    canDeleteSelected,
    canSaveJson,
    isDecorMode: decorModeState.active,
    decorTargetName: decorModeState.targetName,
    enterDecorMode,
    exitDecorMode,
    selectedFigureSizeCm,
    setSelectedFigureSizeCm,
    setSelectedSizeCm,
    commitSelectedTransformChange,
    addFurniture,
    cancelFurniturePlacement,
    deleteSelectedObject,
    deleteSelectedReference,
    rotateSelectedObject,
    setSelectedRotationDegrees,
    setSelectedElevationCm,
    resetSelectedObject,
    saveEditedSceneJson,
    startReplaceSelectedObject,
    undo,
    redo,
    canUndo: historyRef.current.past.length > 1,
    canRedo: historyRef.current.future.length > 0,
    historyVersion,
  };
}
