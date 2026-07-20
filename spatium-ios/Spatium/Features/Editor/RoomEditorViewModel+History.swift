import Foundation

// MARK: - 실행 취소 / 다시 실행

extension RoomEditorViewModel {
    var currentSnapshot: EditorSnapshot {
        EditorSnapshot(
            layout: layout,
            selectedItemID: selectedItemID,
            decoratingItemID: decoratingItemID,
            selectedDecorID: selectedDecorID,
            isMovingSelectedFurniture: isMovingSelectedFurniture
        )
    }

    /// 슬라이더처럼 하나의 손가락 조작이 여러 값 변경을 만드는 경우 시작 상태 하나만 기록한다.
    func beginHistoryTransaction() {
        guard historyTransactionStart == nil else { return }
        historyTransactionStart = currentSnapshot
    }

    func endHistoryTransaction() {
        guard let start = historyTransactionStart else { return }
        historyTransactionStart = nil
        guard start.layout != layout else { return }
        appendUndoSnapshot(start)
    }

    func undo() async {
        endHistoryTransaction()
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(currentSnapshot)
        if redoHistory.count > Self.historyLimit {
            redoHistory.removeFirst(redoHistory.count - Self.historyLimit)
        }
        await applyHistorySnapshot(previous, message: "이전 편집으로 되돌렸어요.")
        updateHistoryAvailability()
    }

    func redo() async {
        endHistoryTransaction()
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(currentSnapshot)
        if undoHistory.count > Self.historyLimit {
            undoHistory.removeFirst(undoHistory.count - Self.historyLimit)
        }
        await applyHistorySnapshot(next, message: "편집을 다시 적용했어요.")
        updateHistoryAvailability()
    }

    func recordHistoryStep() {
        guard historyTransactionStart == nil else { return }
        appendUndoSnapshot(currentSnapshot)
    }

    private func appendUndoSnapshot(_ snapshot: EditorSnapshot) {
        undoHistory.append(snapshot)
        if undoHistory.count > Self.historyLimit {
            undoHistory.removeFirst(undoHistory.count - Self.historyLimit)
        }
        redoHistory.removeAll()
        updateHistoryAvailability()
    }

    private func applyHistorySnapshot(_ snapshot: EditorSnapshot, message: String) async {
        layout = snapshot.layout
        selectedItemID = snapshot.selectedItemID.flatMap { id in
            layout.furnitures.contains(where: { $0.itemId == id }) ? id : nil
        }
        decoratingItemID = snapshot.decoratingItemID.flatMap { id in
            layout.furnitures.contains(where: { $0.itemId == id }) ? id : nil
        }
        decorShelfLevels = decoratingFurniture.map(Self.fallbackDecorShelfLevels) ?? []
        selectedDecorID = snapshot.selectedDecorID
        isMovingSelectedFurniture = selectedItemID != nil && snapshot.isMovingSelectedFurniture
        pendingFigure = nil
        pendingWallResolveItemID = nil
        rebuildLocalIdentifiers()
        sceneRevision += 1
        await refreshUnsavedState()
        statusMessage = message
    }

    func updateHistoryAvailability() {
        canUndo = !undoHistory.isEmpty
        canRedo = !redoHistory.isEmpty
    }

    func rebuildLocalIdentifiers() {
        let smallestItemID = layout.furnitures.map(\.itemId).filter { $0 < 0 }.min() ?? 0
        nextLocalItemID = min(-1, smallestItemID - 1)
        nextDecorID = (layout.furnitures
            .compactMap { $0.decorations?.map(\.decorId).max() }
            .max() ?? 0) + 1
    }
}
