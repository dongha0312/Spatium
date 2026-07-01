import TestThreeEditorPanel from "./components/TestThreeEditorPanel";
import { useTestThreeEditor } from "./hooks/useTestThreeEditor";
import "./TestThreeStagingPage.css";

export default function TestThreeStagingPage() {
  const {
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
  } = useTestThreeEditor();

  return (
    <div className="test-three-page">
      <div ref={containerRef} className="test-three-viewport" />
      <TestThreeEditorPanel
        editedItems={editedItems}
        selectedItem={selectedItem}
        collisionSummary={collisionSummary}
        canResetSelected={canResetSelected}
        canSaveJson={canSaveJson}
        onResetSelected={resetSelectedObject}
        onSaveJson={saveEditedSceneJson}
      />
      {status && <div className="test-three-status">{status}</div>}
      {error && <pre className="test-three-error">{error}</pre>}
    </div>
  );
}
