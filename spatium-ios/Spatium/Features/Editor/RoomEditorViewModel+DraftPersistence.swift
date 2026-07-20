import Foundation

nonisolated struct EditorDraft: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var savedAt: Date
    var layout: RoomLayout
}

/// 에디터 복구본의 JSON 변환과 파일 작업을 앱 전체에서 하나의 utility 큐로 직렬화한다.
/// 여러 에디터 인스턴스의 작업 도착 순서가 바뀌어도 전역 revision으로 최신 명령만 반영한다.
private nonisolated final class RoomEditorDraftIOCoordinator: @unchecked Sendable {
    static let shared = RoomEditorDraftIOCoordinator()

    private let queue = DispatchQueue(
        label: "com.spatium.room-editor-draft-store",
        qos: .utility
    )
    private let revisionLock = NSLock()
    private var nextRevision: UInt64 = 0
    private var latestRevisionByPath: [String: UInt64] = [:]

    func reserveRevision() -> UInt64 {
        revisionLock.lock()
        defer { revisionLock.unlock() }
        nextRevision &+= 1
        return nextRevision
    }

    func load(
        from fileURL: URL,
        operationObserver: (@Sendable (Bool) -> Void)?
    ) async -> EditorDraft? {
        await performWithoutThrowing {
            operationObserver?(Thread.isMainThread)
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let draft = try? decoder.decode(EditorDraft.self, from: data),
                  draft.version == EditorDraft.currentVersion else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            return draft
        }
    }

    func write(
        _ draft: EditorDraft,
        to fileURL: URL,
        directoryURL: URL,
        revision: UInt64,
        operationObserver: (@Sendable (Bool) -> Void)?
    ) async throws -> Bool {
        try await perform { [self] in
            guard shouldApply(revision: revision, to: fileURL) else { return false }
            operationObserver?(Thread.isMainThread)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(draft)
            try data.write(to: fileURL, options: .atomic)
            return true
        }
    }

    func remove(
        at fileURL: URL,
        revision: UInt64,
        operationObserver: (@Sendable (Bool) -> Void)?
    ) async -> Bool {
        await performWithoutThrowing { [self] in
            guard shouldApply(revision: revision, to: fileURL) else { return false }
            operationObserver?(Thread.isMainThread)
            try? FileManager.default.removeItem(at: fileURL)
            return true
        }
    }

    private func shouldApply(revision: UInt64, to fileURL: URL) -> Bool {
        let path = fileURL.standardizedFileURL.path
        guard revision > latestRevisionByPath[path, default: 0] else { return false }
        latestRevisionByPath[path] = revision
        return true
    }

    private func perform<T>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performWithoutThrowing<T>(
        _ operation: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: operation())
            }
        }
    }
}

nonisolated final class RoomEditorDraftDiskStore: @unchecked Sendable {
    private let directoryURL: URL
    private let operationObserver: (@Sendable (Bool) -> Void)?
    private let coordinator = RoomEditorDraftIOCoordinator.shared

    init(
        directoryURL: URL,
        operationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.directoryURL = directoryURL
        self.operationObserver = operationObserver
    }

    func reserveRevision() -> UInt64 {
        coordinator.reserveRevision()
    }

    func load(from fileURL: URL) async -> EditorDraft? {
        await coordinator.load(
            from: fileURL,
            operationObserver: operationObserver
        )
    }

    func write(
        _ draft: EditorDraft,
        to fileURL: URL,
        revision: UInt64
    ) async throws -> Bool {
        try await coordinator.write(
            draft,
            to: fileURL,
            directoryURL: directoryURL,
            revision: revision,
            operationObserver: operationObserver
        )
    }

    func remove(at fileURL: URL, revision: UInt64) async -> Bool {
        await coordinator.remove(
            at: fileURL,
            revision: revision,
            operationObserver: operationObserver
        )
    }
}

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

    func markLayoutChanged() {
        hasUnsavedChanges = true
        scheduleDraftSave()
    }

    func refreshUnsavedState() async {
        hasUnsavedChanges = layout != savedLayout
        if hasUnsavedChanges {
            scheduleDraftSave()
        } else {
            await removeDraftFile()
        }
    }

    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        draftSaveState = .saving
        let revision = draftDiskStore.reserveRevision()
        draftOperationRevision = revision
        draftSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.hasUnsavedChanges else { return }
            await self.writeDraft(layout: self.layout, revision: revision)
            if self.draftOperationRevision == revision {
                self.draftSaveTask = nil
            }
        }
    }

    func persistDraftImmediately() async {
        endHistoryTransaction()
        let hadPendingSave = draftSaveTask != nil
        draftSaveTask?.cancel()
        draftSaveTask = nil
        guard hasUnsavedChanges else { return }
        // 닫기 버튼에서 이미 저장을 기다린 뒤 onDisappear가 연달아 호출돼도
        // 같은 레이아웃을 다시 인코딩하고 쓰지 않는다.
        if !hadPendingSave, draftSaveState.savedAt != nil { return }
        draftSaveState = .saving
        let revision = draftDiskStore.reserveRevision()
        draftOperationRevision = revision
        await writeDraft(layout: layout, revision: revision)
    }

    /// 디스크 권한·용량 문제를 해결한 뒤 현재 편집 상태를 즉시 다시 저장한다.
    func retryDraftSave() async {
        guard hasUnsavedChanges, draftSaveState.failureMessage != nil else { return }
        draftSaveTask?.cancel()
        draftSaveTask = nil
        draftSaveState = .saving
        let revision = draftDiskStore.reserveRevision()
        draftOperationRevision = revision
        await writeDraft(layout: layout, revision: revision)
    }

    private func writeDraft(layout: RoomLayout, revision: UInt64) async {
        let draft = EditorDraft(
            version: EditorDraft.currentVersion,
            savedAt: Date(),
            layout: layout
        )
        do {
            let applied = try await draftDiskStore.write(
                draft,
                to: draftFileURL,
                revision: revision
            )
            guard applied,
                  !Task.isCancelled,
                  draftOperationRevision == revision else { return }
            draftSaveState = .saved(draft.savedAt)
        } catch {
            guard !Task.isCancelled, draftOperationRevision == revision else { return }
            // 서버 저장과 별개로 로컬 복구본이 없다는 사실을 하단 바에 명확히 노출한다.
            draftSaveState = .failed(message: Self.draftSaveFailureMessage)
        }
    }

    func inspectRecoverableDraft() async {
        let fileURL = draftFileURL
        guard let draft = await draftDiskStore.load(from: fileURL) else { return }
        guard draft.layout != savedLayout else {
            await removeDraftFile(at: fileURL)
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

    func discardRecoverableDraft() async {
        pendingRecoverableDraft = nil
        recoverableDraftSavedAt = nil
        hasRecoverableDraft = false
        await removeDraftFile()
    }

    /// 사용자가 명시적으로 '취소'를 선택했을 때는 다음 진입에서 취소한 편집을 다시 묻지 않는다.
    func discardCurrentDraft() async {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        historyTransactionStart = nil
        hasUnsavedChanges = false
        await discardRecoverableDraft()
    }

    func removeDraftFile(
        at fileURL: URL? = nil,
        updatesState: Bool = true
    ) async {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        let revision = draftDiskStore.reserveRevision()
        draftOperationRevision = revision
        let removed = await draftDiskStore.remove(
            at: fileURL ?? draftFileURL,
            revision: revision
        )
        if removed, updatesState, draftOperationRevision == revision {
            draftSaveState = .idle
        }
    }

    func markCurrentLayoutSaved() async {
        savedLayout = layout
        hasUnsavedChanges = false
        await removeDraftFile()
    }
}
