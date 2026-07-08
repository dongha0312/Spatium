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
    status,
    error,
    selectedItem,
    selectedRotationDegrees,
    isReplacingSelected,
    collisionSummary,
    canSaveJson,
    addFurniture,
    deleteSelectedObject,
    setSelectedRotationDegrees,
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

  const handleRotationChange = (event) => {
    setSelectedRotationDegrees(snapRotation(Number(event.target.value)));
  };

  useImperativeHandle(
    ref,
    () => ({
      canSaveJson,
      addFurniture,
      deleteSelectedObject,
      saveEditedSceneJson,
    }),
    [addFurniture, canSaveJson, deleteSelectedObject, saveEditedSceneJson],
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
              <dt>Width</dt>
              <dd>{selectedItem.dimensionsCm?.width ?? "-"} cm</dd>
            </div>
            <div>
              <dt>Depth</dt>
              <dd>{selectedItem.dimensionsCm?.depth ?? "-"} cm</dd>
            </div>
            <div>
              <dt>Height</dt>
              <dd>{selectedItem.dimensionsCm?.height ?? "-"} cm</dd>
            </div>
            <div>
              <dt>Rotation</dt>
              <dd>{selectedRotationDegrees} deg</dd>
            </div>
          </dl>
          {selectedItem.collision?.hasCollision && (
            <div className="room-scene-editor-info-warning">
              Overlap detected
            </div>
          )}
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
          </div>
        </div>
      )}

      {collisionSummary.hasCollision && (
        <div className="room-scene-editor-collision-warning">
          Some items overlap with walls or room boundaries.
        </div>
      )}

      {status && <div className="room-scene-editor-status">{status}</div>}
      {error && <pre className="room-scene-editor-error">{error}</pre>}
    </div>
  );
});

export default RoomSceneEditorPage;
