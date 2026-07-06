import { forwardRef, useImperativeHandle } from "react";
import { useTestThreeEditor } from "./hooks/useTestThreeEditor";
import "./TestThreeStagingPage.css";

const ROTATION_STOPS = [-180, -90, 0, 90, 180];
const ROTATION_SNAP_THRESHOLD = 4;
const REPLACEABLE_TYPES = new Set(["object", "door", "window"]);

function snapRotation(value) {
  const nearest = ROTATION_STOPS.reduce((closest, stop) =>
    Math.abs(stop - value) < Math.abs(closest - value) ? stop : closest,
  );

  return Math.abs(nearest - value) <= ROTATION_SNAP_THRESHOLD
    ? nearest
    : value;
}

const TestThreeStagingPage = forwardRef(function TestThreeStagingPage(
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
  } = useTestThreeEditor({
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
    <div className="test-three-page">
      <div ref={containerRef} className="test-three-viewport" />

      {canShowSelectionControls && (
        <aside className="test-three-info-drawer">
          <div className="test-three-info-title">
            {selectedItem.name || selectedItem.category || "Selected item"}
          </div>
          <div className="test-three-info-subtitle">
            {selectedItem.category || selectedItem.sourceType}
          </div>
          <dl className="test-three-info-list">
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
            <div className="test-three-info-warning">Overlap detected</div>
          )}
        </aside>
      )}

      {canShowSelectionControls && (
        <div className="test-three-selection-controls">
          <div className="test-three-rotation-panel">
            <div className="test-three-rotation-value">
              {selectedRotationDegrees}
            </div>
            <div className="test-three-rotation-track-wrap">
              <input
                type="range"
                className="test-three-rotation-slider"
                min="-180"
                max="180"
                step="1"
                value={selectedRotationDegrees}
                onChange={handleRotationChange}
                aria-label="Rotation degrees"
              />
              <div className="test-three-rotation-ticks" aria-hidden="true">
                {ROTATION_STOPS.map((stop) => (
                  <span key={stop} />
                ))}
              </div>
            </div>
          </div>
          <div className="test-three-selection-toolbar">
            <button
              type="button"
              className={`test-three-selection-tool${
                isReplacingSelected ? " test-three-selection-tool--active" : ""
              }`}
              onClick={startReplaceSelectedObject}
            >
              <span className="test-three-selection-tool-icon">Swap</span>
              Replace
            </button>
            {canDeleteSelected && (
              <button
                type="button"
                className="test-three-selection-tool test-three-selection-tool--danger"
                onClick={deleteSelectedObject}
              >
                <span className="test-three-selection-tool-icon">Del</span>
                Delete
              </button>
            )}
          </div>
        </div>
      )}

      {collisionSummary.hasCollision && (
        <div className="test-three-collision-warning">
          Some items overlap with walls or room boundaries.
        </div>
      )}

      {status && <div className="test-three-status">{status}</div>}
      {error && <pre className="test-three-error">{error}</pre>}
    </div>
  );
});

export default TestThreeStagingPage;
