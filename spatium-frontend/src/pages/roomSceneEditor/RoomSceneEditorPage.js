import { forwardRef, useImperativeHandle } from "react";
import { useRoomSceneEditor } from "./hooks/useRoomSceneEditor";
import "./RoomSceneEditorPage.css";

const ROTATION_STOPS = [-180, -90, 0, 90, 180];
const ROTATION_SNAP_THRESHOLD = 4;
const REPLACEABLE_TYPES = new Set(["object", "door", "window"]);

function snapRotation(value) {
  const nearest = ROTATION_STOPS.reduce((closest, stop) =>
    Math.abs(stop - value) < Math.abs(closest - value) ? stop : closest,
  );

  return Math.abs(nearest - value) <= ROTATION_SNAP_THRESHOLD ? nearest : value;
}

const RoomSceneEditorPage = forwardRef(function RoomSceneEditorPage(
  {
    isSkyview = false,
    showMeasurements = false,
    wallColor = null,
    roomScene = null,
    onSceneChanged,
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
    canSaveJson,
    addFurniture,
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
    roomScene,
    onSceneChanged,
  });

  const canShowSelectionControls = REPLACEABLE_TYPES.has(
    selectedItem?.sourceType,
  );
  const canDeleteSelected = selectedItem?.sourceType === "object";
  const canDeleteReference =
    selectedItem?.sourceType === "door" ||
    selectedItem?.sourceType === "window";
  const canShowElevationControl = selectedItem?.sourceType === "object";

  const handleRotationChange = (event) => {
    setSelectedRotationDegrees(snapRotation(Number(event.target.value)));
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

      {canShowSelectionControls && (
        <aside className="room-scene-editor-info-drawer">
          <div className="room-scene-editor-info-title">
            {selectedItem.name || selectedItem.category || "Selected item"}
          </div>
          <div className="room-scene-editor-info-subtitle">
            {selectedItem.category || selectedItem.sourceType}
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

      {canShowSelectionControls && (
        <div className="room-scene-editor-selection-controls">
          <div className="room-scene-editor-rotation-panel">
            <div className="room-scene-editor-rotation-value">
              {selectedRotationDegrees}
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
          {canShowElevationControl && selectedMaxElevationCm > 0 && (
            <div className="room-scene-editor-elevation-panel">
              <div className="room-scene-editor-elevation-value">
                {selectedElevationCm} cm
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
                교체
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
