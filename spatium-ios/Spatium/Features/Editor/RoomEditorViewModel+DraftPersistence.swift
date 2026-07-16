import Foundation

// MARK: - 로컬 임시 저장 / 복구

extension RoomEditorViewModel {
    var draftFileURL: URL {
        draftDirectoryURL.appendingPathComponent(draftFileName, isDirectory: false)
    }

    static func defaultDraftDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomEditorDrafts", isDirectory: true)
    }

    static func clearDraftDirectoryForUITestingIfRequested(_ directory: URL) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-UITestClearEditorDrafts") else { return }
        try? FileManager.default.removeItem(at: directory)
        #endif
    }

    static func makeDraftFileName(projectID: String?, roomID: String, roomName: String) -> String {
        let key = "\(projectID ?? "standalone")|\(roomID)|\(roomName)"
        // Swift의 hashValue는 실행마다 달라지므로, 재실행 후에도 같은 파일을 찾을 수 있는
        // 고정 FNV-1a 해시를 사용한다.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "\(String(hash, radix: 16)).json"
    }

    static func layoutFingerprint(_ layout: RoomLayout) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(layout)) ?? Data()
    }

    func markLayoutChanged() {
        hasUnsavedChanges = true
        scheduleDraftSave()
    }

    func refreshUnsavedState() {
        hasUnsavedChanges = Self.layoutFingerprint(layout) != savedLayoutFingerprint
        if hasUnsavedChanges {
            scheduleDraftSave()
        } else {
            removeDraftFile()
        }
    }

    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        draftSaveState = .saving
        draftSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self, self.hasUnsavedChanges else { return }
            self.writeDraft(layout: self.layout)
            self.draftSaveTask = nil
        }
    }

    func persistDraftImmediately() {
        endHistoryTransaction()
        draftSaveTask?.cancel()
        draftSaveTask = nil
        guard hasUnsavedChanges else { return }
        writeDraft(layout: layout)
    }

    /// 디스크 권한·용량 문제를 해결한 뒤 현재 편집 상태를 즉시 다시 저장한다.
    func retryDraftSave() {
        guard hasUnsavedChanges, draftSaveState.failureMessage != nil else { return }
        draftSaveTask?.cancel()
        draftSaveTask = nil
        draftSaveState = .saving
        writeDraft(layout: layout)
    }

    private func writeDraft(layout: RoomLayout) {
        do {
            try FileManager.default.createDirectory(
                at: draftDirectoryURL,
                withIntermediateDirectories: true
            )
            let draft = EditorDraft(
                version: EditorDraft.currentVersion,
                savedAt: Date(),
                layout: layout
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(draft)
            try data.write(to: draftFileURL, options: .atomic)
            draftSaveState = .saved(draft.savedAt)
        } catch {
            // 서버 저장과 별개로 로컬 복구본이 없다는 사실을 하단 바에 명확히 노출한다.
            draftSaveState = .failed(message: Self.draftSaveFailureMessage)
        }
    }

    func inspectRecoverableDraft() {
        guard let data = try? Data(contentsOf: draftFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let draft = try? decoder.decode(EditorDraft.self, from: data),
              draft.version == EditorDraft.currentVersion else {
            removeDraftFile()
            return
        }
        guard Self.layoutFingerprint(draft.layout) != savedLayoutFingerprint else {
            removeDraftFile()
            return
        }
        pendingRecoverableDraft = draft
        recoverableDraftSavedAt = draft.savedAt
        hasRecoverableDraft = true
    }

    func restoreRecoverableDraft() {
        guard let draft = pendingRecoverableDraft else { return }
        undoHistory = [currentSnapshot]
        redoHistory.removeAll()
        updateHistoryAvailability()
        pendingRecoverableDraft = nil
        recoverableDraftSavedAt = nil
        hasRecoverableDraft = false
        layout = draft.layout
        selectedItemID = nil
        decoratingItemID = nil
        selectedDecorID = nil
        isMovingSelectedFurniture = false
        rebuildLocalIdentifiers()
        sceneRevision += 1
        markLayoutChanged()
        draftSaveState = .saved(draft.savedAt)
        statusMessage = "임시 저장된 편집을 복구했어요."
    }

    func discardRecoverableDraft() {
        pendingRecoverableDraft = nil
        recoverableDraftSavedAt = nil
        hasRecoverableDraft = false
        removeDraftFile()
    }

    /// 사용자가 명시적으로 '취소'를 선택했을 때는 다음 진입에서 취소한 편집을 다시 묻지 않는다.
    func discardCurrentDraft() {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        historyTransactionStart = nil
        hasUnsavedChanges = false
        discardRecoverableDraft()
    }

    func removeDraftFile() {
        try? FileManager.default.removeItem(at: draftFileURL)
        draftSaveState = .idle
    }

    func markCurrentLayoutSaved() {
        savedLayoutFingerprint = Self.layoutFingerprint(layout)
        hasUnsavedChanges = false
        removeDraftFile()
    }
}
