import { forwardRef, useEffect, useImperativeHandle } from "react";
import { useRoomSceneEditor } from "./hooks/useRoomSceneEditor";
import { isDecoratableModelPath } from "./scene/decorSurface";
import "./RoomSceneEditorPage.css";

const ROTATION_STOPS = [-180, -90, 0, 90, 180];
const REPLACEABLE_TYPES = new Set([
  "object",
  "door",
  "window",
  "opening",
  "figure",
]);

// Three.js 씬(useRoomSceneEditor)을 렌더링하는 뷰포트 + 선택된 오브젝트의 정보 패널/
// 회전·높이 슬라이더/교체·삭제 툴바를 그리는 컴포넌트. 상위(3dEditor.js)는 ref를 통해
// addFurniture/저장/삭제 같은 액션을 호출한다.
const RoomSceneEditorPage = forwardRef(function RoomSceneEditorPage(
  {
    isSkyview = false,
    isPersonView = false,
    showMeasurements = false,
    wallColor = null,
    floorColor = null,
    roomScene = null,
    onSceneChanged,
    onFloorColorLoaded,
    onDecorModeChanged,
  },
  ref,
) {
  const {
    containerRef,
    error,
    selectedItem,
    selectedRotationDegrees,
    selectedElevationCm,
    selectedMaxElevationCm,
    selectedSizeCm,
    isReplacingSelected,
    isPlacingFurniture,
    canSaveJson,
    isDecorMode,
    decorTargetName,
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
    setSelectedRotationDegrees,
    setSelectedElevationCm,
    saveEditedSceneJson,
    startReplaceSelectedObject,
    undo,
    redo,
    canUndo,
    canRedo,
  } = useRoomSceneEditor({
    isSkyview,
    isPersonView,
    showMeasurements,
    wallColor,
    floorColor,
    roomScene,
    onSceneChanged,
    onFloorColorLoaded,
  });

  // 상위 화면(3dEditor.js)이 꾸미기 모드에 맞춰 카탈로그 필터/Skyview 버튼 등을
  // 바꿀 수 있게 모드 변경을 알려준다.
  useEffect(() => {
    onDecorModeChanged?.(isDecorMode);
  }, [isDecorMode, onDecorModeChanged]);

  // 선택된 오브젝트 종류에 따라 어떤 컨트롤을 보여줄지 결정한다.
  const canShowSelectionControls = REPLACEABLE_TYPES.has(
    selectedItem?.sourceType,
  );
  const isFigureSelected = selectedItem?.sourceType === "figure";
  const canDeleteSelected =
    selectedItem?.sourceType === "object" || isFigureSelected;
  const canDeleteReference =
    selectedItem?.sourceType === "door" ||
    selectedItem?.sourceType === "window";
  const canShowElevationControl = selectedItem?.sourceType === "object";
  const canShowSizeControl = selectedItem?.sourceType === "object";
  const isOpeningSelected = selectedItem?.sourceType === "opening";
  // 꾸미기 전용 모델(editable_furniture 폴더 GLB)을 선택했을 때만
  // "서랍장 꾸미기" 버튼을 보여준다.
  const canDecorateSelected =
    !isDecorMode &&
    selectedItem?.sourceType === "object" &&
    isDecoratableModelPath(selectedItem?.path || selectedItem?.modelUrl);

  const handleRotationChange = (event) => {
    setSelectedRotationDegrees(Number(event.target.value));
  };

  const handleElevationChange = (event) => {
    setSelectedElevationCm(Number(event.target.value));
  };

  const handleFigureSizeChange = (event) => {
    setSelectedFigureSizeCm(Number(event.target.value));
  };

  const handleSizeChange = (event) => {
    setSelectedSizeCm(Number(event.target.value));
  };

  const commitSliderChange = () => {
    commitSelectedTransformChange();
  };

  const handleDeleteAsOpening = () => {
    deleteSelectedReference(false);
  };

  const handleDeleteFillWithWall = () => {
    const confirmed = window.confirm(
      "선택한 문/창문을 삭제하고 벽으로 메우시겠습니까? 이 작업은 되돌릴 수 없습니다.",
    );
    if (!confirmed) return;
    deleteSelectedReference(true);
  };

  // 상위 컴포넌트(3dEditor.js)가 editorRef.current.xxx() 형태로 호출할 수 있게
  // 내부 액션 일부를 ref로 노출한다.
  useImperativeHandle(
    ref,
    () => ({
      canSaveJson,
      addFurniture,
      deleteSelectedObject,
      saveEditedSceneJson,
      isReplacingSelected,
    }),
    [
      addFurniture,
      canSaveJson,
      deleteSelectedObject,
      saveEditedSceneJson,
      isReplacingSelected,
    ],
  );

  return (
    <div className="room-scene-editor-page">
      <div ref={containerRef} className="room-scene-editor-viewport" />

      <div className="room-scene-editor-history-toolbar" aria-label="편집 이력">
        <button type="button" onClick={undo} disabled={!canUndo} title="Undo">
          되돌리기
        </button>
        <button type="button" onClick={redo} disabled={!canRedo} title="Redo">
          다시 실행
        </button>
      </div>

      {isPersonView && (
        <div className="room-scene-editor-person-banner">
          1인칭 시점 · WASD/방향키로 이동 · 드래그로 시야 회전
        </div>
      )}

      {/* 서랍장 꾸미기 모드 배너 — 완료 버튼으로 원래 시점에 복귀한다 */}
      {isDecorMode && (
        <div className="room-scene-editor-placement-banner room-scene-editor-decor-banner">
          <span>
            {decorTargetName || "서랍장"} 꾸미기 — 왼쪽 목록에서 피규어를
            클릭해 올려놓고, 드래그로 위치를 조정하세요.
          </span>
          <button
            type="button"
            className="room-scene-editor-placement-cancel room-scene-editor-decor-done"
            onClick={exitDecorMode}
          >
            완료
          </button>
        </div>
      )}

      {/* 가구/피규어 배치 모드 안내 배너 — 위치를 클릭할 때까지 표시된다.
          꾸미기 모드 중에는 꾸미기 배너 아래에 겹치지 않게 표시한다. */}
      {isPlacingFurniture && (
        <div
          className={`room-scene-editor-placement-banner${
            isDecorMode ? " room-scene-editor-placement-banner--stacked" : ""
          }`}
        >
          <span>
            {isDecorMode
              ? "피규어를 놓을 층(선반)을 클릭하세요."
              : "가구를 놓을 위치를 바닥에서 클릭하세요."}
          </span>
          <button
            type="button"
            className="room-scene-editor-placement-cancel"
            onClick={cancelFurniturePlacement}
          >
            취소
          </button>
        </div>
      )}

      {/* 선택된 오브젝트의 치수/회전/높이 정보 패널 */}
      {canShowSelectionControls && !isPersonView && (
        <aside className="room-scene-editor-info-drawer">
          <div className="room-scene-editor-info-title">
            {selectedItem.name || selectedItem.category || "Selected item"}
          </div>
          <div className="room-scene-editor-info-subtitle">
            {isOpeningSelected
              ? "개구부"
              : isFigureSelected
                ? "피규어"
                : selectedItem.category || selectedItem.sourceType}
          </div>
          <dl className="room-scene-editor-info-list">
            <div>
              <dt>가로</dt>
              <dd>{(selectedItem.currentDimensionsCm || selectedItem.dimensionsCm)?.width ?? "-"} cm</dd>
            </div>
            <div>
              <dt>세로</dt>
              <dd>{(selectedItem.currentDimensionsCm || selectedItem.dimensionsCm)?.depth ?? "-"} cm</dd>
            </div>
            <div>
              <dt>높이</dt>
              <dd>{(selectedItem.currentDimensionsCm || selectedItem.dimensionsCm)?.height ?? "-"} cm</dd>
            </div>
            <div>
              <dt>각도</dt>
              <dd>{selectedRotationDegrees} 도</dd>
            </div>
            {canShowElevationControl && (
              <div>
                <dt>바닥과 높이 차이</dt>
                <dd>{selectedElevationCm} cm</dd>
              </div>
            )}
          </dl>
        </aside>
      )}

      {/* 회전/높이 슬라이더 + 교체·삭제 툴바 */}
      {canShowSelectionControls && !isPersonView && (
        <div className="room-scene-editor-selection-controls">
          {/* 개구부는 벽에 고정된 자리라서 자유 회전이 의미 없다(벽과 바로 충돌한다) */}
          {!isOpeningSelected && (
            <div className="room-scene-editor-rotation-panel">
              <div className="room-scene-editor-rotation-value">
                회전 : {selectedRotationDegrees}도
              </div>
              <div className="room-scene-editor-rotation-track-wrap">
                <input
                  type="range"
                  className="room-scene-editor-rotation-slider"
                  min="-180"
                  max="180"
                  step="1"
                  value={selectedRotationDegrees}
                  onChange={handleRotationChange}
                  onPointerUp={commitSliderChange}
                  onPointerCancel={commitSliderChange}
                  onKeyUp={commitSliderChange}
                  onBlur={commitSliderChange}
                  aria-label="Rotation degrees"
                />
                <div
                  className="room-scene-editor-rotation-ticks"
                  aria-hidden="true"
                >
                  {ROTATION_STOPS.map((stop) => (
                    <span key={stop} />
                  ))}
                </div>
              </div>
            </div>
          )}
          {/* 피규어 크기 슬라이더 — 최대 변 길이(cm) 기준 균일 스케일 */}
          {isFigureSelected && selectedFigureSizeCm > 0 && (
            <div className="room-scene-editor-elevation-panel">
              <div className="room-scene-editor-elevation-value">
                크기 : {selectedFigureSizeCm}cm
              </div>
              <div className="room-scene-editor-elevation-track-wrap">
                <input
                  type="range"
                  className="room-scene-editor-elevation-slider"
                  min="5"
                  max="50"
                  step="1"
                  value={selectedFigureSizeCm}
                  onChange={handleFigureSizeChange}
                  onPointerUp={commitSliderChange}
                  onPointerCancel={commitSliderChange}
                  onKeyUp={commitSliderChange}
                  onBlur={commitSliderChange}
                  aria-label="Figure size"
                />
              </div>
            </div>
          )}
          {canShowSizeControl && selectedSizeCm > 0 && (
            <div className="room-scene-editor-elevation-panel">
              <div className="room-scene-editor-elevation-value">
                가구 크기 : {selectedSizeCm}cm
              </div>
              <div className="room-scene-editor-elevation-track-wrap">
                <input
                  type="range"
                  className="room-scene-editor-elevation-slider"
                  min="10"
                  max="500"
                  step="1"
                  value={selectedSizeCm}
                  onChange={handleSizeChange}
                  onPointerUp={commitSliderChange}
                  onPointerCancel={commitSliderChange}
                  onKeyUp={commitSliderChange}
                  onBlur={commitSliderChange}
                  aria-label="Furniture size"
                />
              </div>
            </div>
          )}
          {canShowElevationControl && selectedMaxElevationCm > 0 && (
            <div className="room-scene-editor-elevation-panel">
              <div className="room-scene-editor-elevation-value">
                바닥과의 높이 : {selectedElevationCm}cm
              </div>
              <div className="room-scene-editor-elevation-track-wrap">
                <input
                  type="range"
                  className="room-scene-editor-elevation-slider"
                  min="0"
                  max={selectedMaxElevationCm}
                  step="1"
                  value={selectedElevationCm}
                  onChange={handleElevationChange}
                  onPointerUp={commitSliderChange}
                  onPointerCancel={commitSliderChange}
                  onKeyUp={commitSliderChange}
                  onBlur={commitSliderChange}
                  aria-label="Elevation from floor"
                />
              </div>
            </div>
          )}
          <div className="room-scene-editor-selection-toolbar">
            {canDecorateSelected && (
              <button
                type="button"
                className="room-scene-editor-selection-tool room-scene-editor-selection-tool--decor"
                onClick={enterDecorMode}
                title="서랍장을 정면에서 보며 피규어를 올려놓습니다"
              >
                <span className="room-scene-editor-selection-tool-icon">
                  서랍장 꾸미기
                </span>
              </button>
            )}
            <button
              type="button"
              className={`room-scene-editor-selection-tool${
                isReplacingSelected
                  ? " room-scene-editor-selection-tool--active"
                  : ""
              }`}
              onClick={startReplaceSelectedObject}
            >
              <span className="room-scene-editor-selection-tool-icon">
                {isOpeningSelected ? "채우기" : "교체"}
              </span>
            </button>
            {canDeleteSelected && (
              <button
                type="button"
                className="room-scene-editor-selection-tool room-scene-editor-selection-tool--danger"
                onClick={deleteSelectedObject}
              >
                <span className="room-scene-editor-selection-tool-icon">
                  삭제
                </span>
              </button>
            )}
            {canDeleteReference && (
              <>
                <button
                  type="button"
                  className="room-scene-editor-selection-tool"
                  onClick={handleDeleteAsOpening}
                  title="문/창문만 지우고 개구부는 남깁니다"
                >
                  <span className="room-scene-editor-selection-tool-icon">
                    개구부로 삭제
                  </span>
                </button>
                <button
                  type="button"
                  className="room-scene-editor-selection-tool room-scene-editor-selection-tool--danger"
                  onClick={handleDeleteFillWithWall}
                  title="문/창문을 지우고 그 자리를 벽으로 메웁니다"
                >
                  <span className="room-scene-editor-selection-tool-icon">
                    벽으로 메우기
                  </span>
                </button>
              </>
            )}
          </div>
        </div>
      )}

      {error && <pre className="room-scene-editor-error">{error}</pre>}
    </div>
  );
});

export default RoomSceneEditorPage;
