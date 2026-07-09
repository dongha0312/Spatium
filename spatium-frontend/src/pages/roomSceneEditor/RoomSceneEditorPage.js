import { forwardRef, useImperativeHandle } from "react";
import { useRoomSceneEditor } from "./hooks/useRoomSceneEditor";
import "./RoomSceneEditorPage.css";

const ROTATION_STOPS = [-180, -90, 0, 90, 180];
const REPLACEABLE_TYPES = new Set(["object", "door", "window", "opening"]);

// Three.js 씬(useRoomSceneEditor)을 렌더링하는 뷰포트 + 선택된 오브젝트의 정보 패널/
// 회전·높이 슬라이더/교체·삭제 툴바를 그리는 컴포넌트. 상위(3dEditor.js)는 ref를 통해
// addFurniture/저장/삭제 같은 액션을 호출한다.
const RoomSceneEditorPage = forwardRef(function RoomSceneEditorPage(
  {
    isSkyview = false,
    showMeasurements = false,
    wallColor = null,
    floorColor = null,
    roomScene = null,
    onSceneChanged,
    onFloorColorLoaded,
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
    isReplacingSelected,
    isPlacingFurniture,
    canSaveJson,
    addFurniture,
    cancelFurniturePlacement,
    deleteSelectedObject,
    deleteSelectedReference,
    setSelectedRotationDegrees,
    setSelectedElevationCm,
    saveEditedSceneJson,
    startReplaceSelectedObject,
  } = useRoomSceneEditor({
    isSkyview,
    showMeasurements,
    wallColor,
    floorColor,
    roomScene,
    onSceneChanged,
    onFloorColorLoaded,
  });

  // 선택된 오브젝트 종류에 따라 어떤 컨트롤을 보여줄지 결정한다.
  const canShowSelectionControls = REPLACEABLE_TYPES.has(
    selectedItem?.sourceType,
  );
  const canDeleteSelected = selectedItem?.sourceType === "object";
  const canDeleteReference =
    selectedItem?.sourceType === "door" ||
    selectedItem?.sourceType === "window";
  const canShowElevationControl = selectedItem?.sourceType === "object";
  const isOpeningSelected = selectedItem?.sourceType === "opening";

  const handleRotationChange = (event) => {
    setSelectedRotationDegrees(Number(event.target.value));
  };

  const handleElevationChange = (event) => {
    setSelectedElevationCm(Number(event.target.value));
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

      {/* 가구 배치 모드 안내 배너 — 바닥을 클릭할 때까지 표시된다 */}
      {isPlacingFurniture && (
        <div className="room-scene-editor-placement-banner">
          <span>가구를 놓을 위치를 바닥에서 클릭하세요.</span>
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
      {canShowSelectionControls && (
        <aside className="room-scene-editor-info-drawer">
          <div className="room-scene-editor-info-title">
            {selectedItem.name || selectedItem.category || "Selected item"}
          </div>
          <div className="room-scene-editor-info-subtitle">
            {isOpeningSelected
              ? "개구부"
              : selectedItem.category || selectedItem.sourceType}
          </div>
          <dl className="room-scene-editor-info-list">
            <div>
              <dt>가로</dt>
              <dd>{selectedItem.dimensionsCm?.width ?? "-"} cm</dd>
            </div>
            <div>
              <dt>세로</dt>
              <dd>{selectedItem.dimensionsCm?.depth ?? "-"} cm</dd>
            </div>
            <div>
              <dt>높이</dt>
              <dd>{selectedItem.dimensionsCm?.height ?? "-"} cm</dd>
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
      {canShowSelectionControls && (
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
                  aria-label="Elevation from floor"
                />
              </div>
            </div>
          )}
          <div className="room-scene-editor-selection-toolbar">
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
