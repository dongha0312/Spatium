export default function TestThreeEditorPanel({
  editedItems,
  selectedItem,
  collisionSummary,
  canResetSelected,
  canSaveJson,
  onResetSelected,
  onSaveJson,
}) {
  return (
    <aside className="test-three-panel">
      <h1 className="test-three-title">Furniture Edit</h1>
      <div className="test-three-actions">
        <button
          type="button"
          onClick={onResetSelected}
          disabled={!canResetSelected}
          className="test-three-button test-three-button--secondary"
        >
          Reset
        </button>
        <button
          type="button"
          onClick={onSaveJson}
          disabled={!canSaveJson}
          className="test-three-button test-three-button--primary"
        >
          Save JSON
        </button>
      </div>
      <p className="test-three-count">{editedItems.length} editable objects</p>
      <div
        className={`test-three-collision ${
          collisionSummary.hasCollision
            ? "test-three-collision--active"
            : "test-three-collision--clear"
        }`}
      >
        {collisionSummary.hasCollision
          ? `Collision: ${collisionSummary.with.join(", ")}`
          : "Collision: clear"}
      </div>
      <pre className="test-three-json-preview">
        {JSON.stringify(selectedItem || editedItems[0] || {}, null, 2)}
      </pre>
    </aside>
  );
}
