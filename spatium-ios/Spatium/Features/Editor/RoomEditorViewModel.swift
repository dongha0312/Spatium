import Combine
import Foundation
import UIKit

enum EditorDraftSaveState: Equatable {
    case idle
    case saving
    case saved(Date)
    case failed(message: String)

    var savedAt: Date? {
        if case let .saved(date) = self { return date }
        return nil
    }

    var failureMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}

/// VoiceOver 등 3D 캔버스를 직접 탭하기 어려운 사용자가 선택할 수 있는 책장 지지면.
struct DecorShelfLevel: Identifiable, Equatable {
    let id: Int
    let title: String
    let height: Double
}

@MainActor
final class RoomEditorViewModel: ObservableObject {
    @Published var layout: RoomLayout
    @Published var viewMode: RoomViewMode = .threeD
    @Published var selectedItemID: Int?
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var isOffline = false
    /// 마지막 저장(저장하기) 이후 편집이 있었는지. 방 전환/이탈 경고에 사용합니다.
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var hasRecoverableDraft = false
    @Published private(set) var recoverableDraftSavedAt: Date?
    @Published private(set) var draftSaveState: EditorDraftSaveState = .idle
    /// 하단 뷰바의 "측정" 모드 on/off (프런트엔드와 동일하게 배지/치수 표시 전환).
    @Published var isMeasuring = false
    /// 선택한 가구를 드래그로 이동하는 편집 상태. 측정 모드와 분리합니다.
    @Published var isMovingSelectedFurniture = false

    // MARK: 책장 꾸미기(피규어) 상태 — 프런트엔드 decorMode 대응

    /// 꾸미기 중인 책장의 itemId. nil이 아니면 에디터가 꾸미기 모드다.
    @Published var decoratingItemID: Int?
    /// 목록에서 골라 "선반 탭 배치"를 기다리는 피규어.
    @Published var pendingFigure: FurnitureCatalogItem?
    /// 꾸미기 중인 책장 위에서 선택된 피규어의 decorId.
    @Published var selectedDecorID: Int?
    /// 3D 책장 모델에서 찾은 선반 높이. 모델 분석 전에는 책장 높이 기반 기본 3단을 제공한다.
    @Published private(set) var decorShelfLevels: [DecorShelfLevel] = []
    private var nextDecorID = 1

    /// 회전 슬라이더가 스냅되는 각도 스톱(도).
    static let rotationStops: [Double] = [-180, -90, 0, 90, 180]
    /// 접근성 이동 버튼 한 번에 움직이는 거리(m).
    static let decorNudgeStep = 0.05

    /// Bumped whenever furniture geometry needs a full scene rebuild
    /// (add/remove/replace) — transform-only edits mutate nodes in place.
    @Published var sceneRevision = 0

    /// 교체/추가로 발자국이 커진 가구가 벽을 뚫고 나가지 않도록, 씬 쪽에 벽 밖 밀어내기
    /// (웹 pushObjectOutOfWalls 대응)를 요청하는 아이템 ID. 씬이 처리 후 nil로 되돌린다.
    @Published var pendingWallResolveItemID: Int?

    /// 서버 룸 ID. 스캔에서 바로 연 룸은 "local-scan"으로 시작했다가 저장 시 업로드되면 서버 ID로 바뀝니다.
    private(set) var roomID: String
    /// 저장(POST /api/rooms/save)에 필요한 소속 프로젝트 ID. 스캔에서 바로 연 경우 nil.
    let projectID: String?
    /// 툴바에 표시할 소속 프로젝트 이름. 스캔에서 바로 연 경우 nil.
    let projectName: String?
    /// 스캔한 방 메시(USDZ). 있으면 씬이 박스 방 대신 실제 스캔 메시를 배경으로 깝니다.
    let usdzURL: URL?
    /// 서버 레이아웃을 시도할지 여부. 스캔에서 바로 연 편집기는 로컬 전용입니다.
    private let loadsRemoteLayout: Bool
    /// 서버 레이아웃을 실제로 받아왔는지. 폴백(빈) 에디터에서 저장해 기존 서버
    /// 메타데이터를 빈 목록으로 덮어쓰는 사고를 막는 데 사용합니다.
    private var remoteLayoutLoaded = false
    /// 저장 과정에서 새 서버 룸이 생성됐을 때(스캔 첫 업로드) 바깥 상태에 알리는 콜백.
    /// 이를 전달하지 않으면 스캔 화면의 "서버로 업로드"가 같은 스캔으로 중복 룸을 만든다.
    var onServerRoomCreated: ((RoomRecord) -> Void)?
    private var nextLocalItemID = -1
    /// 새 가구가 앉을 바닥 높이(월드 Y). 박스 방은 0, 스캔 방은 감지 가구 바닥에서 유도.
    private var floorY: Double = 0

    private struct EditorSnapshot {
        var layout: RoomLayout
        var selectedItemID: Int?
        var decoratingItemID: Int?
        var selectedDecorID: Int?
        var isMovingSelectedFurniture: Bool
    }

    private struct EditorDraft: Codable {
        static let currentVersion = 1

        var version: Int
        var savedAt: Date
        var layout: RoomLayout
    }

    private static let historyLimit = 30
    static let draftSaveFailureMessage = "이 기기에 임시 저장하지 못했어요. 저장 공간을 확인한 후 다시 시도해 주세요."
    private var undoHistory: [EditorSnapshot] = []
    private var redoHistory: [EditorSnapshot] = []
    private var historyTransactionStart: EditorSnapshot?
    private var savedLayoutFingerprint = Data()
    private var pendingRecoverableDraft: EditorDraft?
    private var draftSaveTask: Task<Void, Never>?
    private let draftDirectoryURL: URL
    private var draftFileName: String

    var selectedFurniture: PlacedFurniture? {
        guard let selectedItemID else { return nil }
        return layout.furnitures.first { $0.itemId == selectedItemID }
    }

    var draftSavedAt: Date? {
        draftSaveState.savedAt
    }

    init(
        room: RoomRecord,
        projectID: String? = nil,
        projectName: String? = nil,
        draftDirectoryURL: URL? = nil
    ) {
        self.roomID = room.id
        self.projectID = projectID
        self.projectName = projectName
        self.usdzURL = nil
        self.loadsRemoteLayout = true
        self.draftDirectoryURL = draftDirectoryURL ?? Self.defaultDraftDirectoryURL()
        Self.clearDraftDirectoryForUITestingIfRequested(self.draftDirectoryURL)
        self.draftFileName = Self.makeDraftFileName(
            projectID: projectID,
            roomID: room.id,
            roomName: room.roomType
        )
        self.layout = RoomLayout(
            roomId: room.id,
            roomName: room.roomType,
            viewMode: .threeD,
            space: RoomSpace(
                spaceId: room.id,
                name: room.roomType,
                area: room.area ?? 16,
                ceilingHeight: 2.4,
                wallColor: "#F2EDE5"
            ),
            furnitures: []
        )
        self.savedLayoutFingerprint = Self.layoutFingerprint(self.layout)
    }

    /// 스캔 결과로 바로 여는 3D 에디터. 실제 스캔 메시(usdzURL) 위에
    /// 감지된 객체를 편집 가능한 가구로 올려 시작합니다.
    init(
        scanItems: [EditableScanItem],
        roomName: String,
        usdzURL: URL?,
        initialFloorColor: String? = nil,
        area: Double,
        ceilingHeight: Double,
        roomID: String? = nil,
        projectID: String? = nil,
        projectName: String? = nil,
        draftDirectoryURL: URL? = nil
    ) {
        self.roomID = roomID ?? "local-scan"
        self.projectID = projectID
        self.projectName = projectName
        self.usdzURL = usdzURL
        self.loadsRemoteLayout = false
        self.draftDirectoryURL = draftDirectoryURL ?? Self.defaultDraftDirectoryURL()
        Self.clearDraftDirectoryForUITestingIfRequested(self.draftDirectoryURL)
        self.draftFileName = Self.makeDraftFileName(
            projectID: projectID,
            roomID: roomID ?? "local-scan",
            roomName: roomName
        )
        // 서버 룸(projectID 있음)을 씬으로 열면 온라인 저장이 가능하므로 오프라인 표시하지 않는다.
        self.isOffline = (projectID == nil)
        self.layout = RoomLayout(
            roomId: roomID ?? "local-scan",
            roomName: roomName,
            viewMode: .threeD,
            space: RoomSpace(
                spaceId: roomID ?? "local-scan",
                name: roomName,
                area: max(area, 4),
                ceilingHeight: ceilingHeight,
                wallColor: "#F2EDE5",
                floorColor: initialFloorColor
            ),
            furnitures: []
        )
        // 문/창문도 모델이 있으므로 별도 렌더 대상으로 올립니다. 개구부는 열린 공간이라 제외합니다.
        var nextID = -1
        self.layout.furnitures = scanItems.filter { $0.sourceType != "개구부" }.map { item in
            defer { nextID -= 1 }
            let category = item.detectedCategory.isEmpty ? item.sourceType : item.detectedCategory
            return PlacedFurniture(
                itemId: nextID,
                furnitureId: abs(item.id.hashValue),
                furnitureName: category,
                // RoomPlan 좌표는 중심 높이이므로 바닥면으로 내려 배치.
                position: .init(x: item.positionX, y: item.positionY - item.height / 2, z: item.positionZ),
                rotation: .init(x: 0, y: item.detectedRotationY + item.rotationY, z: 0),
                scale: .one,
                width: item.width,
                depth: item.depth,
                height: item.height,
                modelName: item.modelName ?? FurnitureCatalog.defaultModelName(matching: "\(category) \(item.sourceType)"),
                decorations: item.decorations
            )
        }
        self.nextLocalItemID = nextID
        // 저장된 피규어 decorId와 새로 올릴 피규어 id가 겹치지 않게 이어서 발급한다.
        self.nextDecorID = (self.layout.furnitures
            .compactMap { $0.decorations?.map(\.decorId).max() }
            .max() ?? 0) + 1
        // 감지된 가구들의 바닥면(= 스캔 바닥 높이)을 새 가구 배치 기준으로 삼습니다.
        // 씬이 방 메시에서 실제 바닥을 찾으면 adoptFloorY로 이 값을 교정합니다.
        // (가구를 모두 띄워 저장한 방에서 띄운 높이가 새 바닥으로 굳는 것 방지)
        // 벽 밀착/충돌은 씬(RoomEditorSceneView)의 벽 시스템이 렌더·드래그 모두에서 일관되게 처리합니다.
        self.floorY = self.layout.furnitures.map { $0.position.y }.min() ?? 0
        self.savedLayoutFingerprint = Self.layoutFingerprint(self.layout)

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestMeasure") {
            self.isMeasuring = true
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestSkyview") {
            self.viewMode = .skyView
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestPerson") {
            self.viewMode = .person
        }
        #endif
    }

    // MARK: - 실행 취소 / 다시 실행

    private var currentSnapshot: EditorSnapshot {
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
        guard Self.layoutFingerprint(start.layout) != Self.layoutFingerprint(layout) else { return }
        appendUndoSnapshot(start)
    }

    func undo() {
        endHistoryTransaction()
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(currentSnapshot)
        if redoHistory.count > Self.historyLimit {
            redoHistory.removeFirst(redoHistory.count - Self.historyLimit)
        }
        applyHistorySnapshot(previous, message: "이전 편집으로 되돌렸어요.")
        updateHistoryAvailability()
    }

    func redo() {
        endHistoryTransaction()
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(currentSnapshot)
        if undoHistory.count > Self.historyLimit {
            undoHistory.removeFirst(undoHistory.count - Self.historyLimit)
        }
        applyHistorySnapshot(next, message: "편집을 다시 적용했어요.")
        updateHistoryAvailability()
    }

    private func recordHistoryStep() {
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

    private func applyHistorySnapshot(_ snapshot: EditorSnapshot, message: String) {
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
        refreshUnsavedState()
        statusMessage = message
    }

    private func updateHistoryAvailability() {
        canUndo = !undoHistory.isEmpty
        canRedo = !redoHistory.isEmpty
    }

    private func rebuildLocalIdentifiers() {
        let smallestItemID = layout.furnitures.map(\.itemId).filter { $0 < 0 }.min() ?? 0
        nextLocalItemID = min(-1, smallestItemID - 1)
        nextDecorID = (layout.furnitures
            .compactMap { $0.decorations?.map(\.decorId).max() }
            .max() ?? 0) + 1
    }

    // MARK: - 로컬 임시 저장 / 복구

    private var draftFileURL: URL {
        draftDirectoryURL.appendingPathComponent(draftFileName, isDirectory: false)
    }

    private static func defaultDraftDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomEditorDrafts", isDirectory: true)
    }

    private static func clearDraftDirectoryForUITestingIfRequested(_ directory: URL) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-UITestClearEditorDrafts") else { return }
        try? FileManager.default.removeItem(at: directory)
        #endif
    }

    private static func makeDraftFileName(projectID: String?, roomID: String, roomName: String) -> String {
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

    private static func layoutFingerprint(_ layout: RoomLayout) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(layout)) ?? Data()
    }

    private func markLayoutChanged() {
        hasUnsavedChanges = true
        scheduleDraftSave()
    }

    private func refreshUnsavedState() {
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

    private func inspectRecoverableDraft() {
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

    private func removeDraftFile() {
        try? FileManager.default.removeItem(at: draftFileURL)
        draftSaveState = .idle
    }

    private func markCurrentLayoutSaved() {
        savedLayoutFingerprint = Self.layoutFingerprint(layout)
        hasUnsavedChanges = false
        removeDraftFile()
    }

    func loadLayout() async {
        // 스캔에서 바로 연 편집기는 실제 스캔 메시 + 감지 가구로 이미 구성돼 있으니 서버 조회를 건너뜁니다.
        guard loadsRemoteLayout else {
            sceneRevision += 1
            inspectRecoverableDraft()
            return
        }
        // 백엔드에는 별도 레이아웃 조회 API가 없다. 서버 룸의 실제 배치는 scene(metadata)
        // 응답으로 여는 씬 에디터가 담당하고, 이 경로(폴백 박스 에디터)는 방 데이터를 받지
        // 못한 상태다. 네트워크 문제처럼 보이지 않게 상태를 그대로 알려주고,
        // remoteLayoutLoaded=false 가드가 빈 레이아웃으로 서버를 덮어쓰는 저장을 막는다.
        isOffline = true
        statusMessage = "방 데이터를 불러오지 못해 이 기기에서만 편집합니다."
        sceneRevision += 1
        inspectRecoverableDraft()
    }

    func place(furniture: FurnitureDetail) {
        guard viewMode != .person else {
            statusMessage = "1인칭 시점에서는 가구를 추가할 수 없어요"
            return
        }
        recordHistoryStep()
        let placed = PlacedFurniture(
            itemId: takeLocalItemID(),
            furnitureId: furniture.furnitureId,
            furnitureName: furniture.name,
            // 스캔 방은 바닥이 y=0이 아닐 수 있으므로 실제 바닥 높이에 놓는다.
            position: .init(x: 0, y: floorY, z: 0),
            rotation: .zero,
            scale: .one,
            width: furniture.width,
            depth: furniture.depth,
            height: furniture.height
        )
        layout.furnitures.append(placed)
        markLayoutChanged()
        selectedItemID = placed.itemId
        isMovingSelectedFurniture = true
        sceneRevision += 1
    }

    func commitTransform(itemID: Int, transform: FurnitureTransform, recordHistory: Bool = true) {
        guard let index = layout.furnitures.firstIndex(where: { $0.itemId == itemID }) else { return }
        let current = FurnitureTransform(
            position: layout.furnitures[index].position,
            rotation: layout.furnitures[index].rotation,
            scale: layout.furnitures[index].scale
        )
        guard current != transform else { return }
        if recordHistory { recordHistoryStep() }
        layout.furnitures[index].position = transform.position
        layout.furnitures[index].rotation = transform.rotation
        layout.furnitures[index].scale = transform.scale
        markLayoutChanged()
    }

    func rotateSelected(byDegrees degrees: Double) {
        guard let item = selectedFurniture, !Self.isWallInfill(item) else { return }
        var rotation = item.rotation
        rotation.y += degrees * .pi / 180
        commitTransform(
            itemID: item.itemId,
            transform: FurnitureTransform(position: item.position, rotation: rotation, scale: item.scale)
        )
        sceneRevision += 1
    }

    // MARK: - 3D 에디터 페이지(프런트엔드 대응) 기능

    /// 카탈로그 상품을 방에 배치합니다. 선택한 정확한 GLB 파일명을 함께 실어 렌더합니다.
    /// 여러 개 추가 시 원점에 겹치지 않도록 작은 격자로 흩어 놓습니다.
    func place(catalogItem: FurnitureCatalogItem) {
        guard viewMode != .person else {
            statusMessage = "1인칭 시점에서는 가구를 추가할 수 없어요"
            return
        }
        recordHistoryStep()
        let n = layout.furnitures.count
        let col = Double(n % 3) - 1        // -1, 0, 1
        let row = Double(n / 3)
        let placed = PlacedFurniture(
            itemId: takeLocalItemID(),
            furnitureId: abs(catalogItem.id.hashValue),
            furnitureName: catalogItem.name,
            position: .init(x: col * 0.6, y: floorY, z: row * 0.6),
            rotation: .zero,
            scale: .one,
            width: catalogItem.width,
            depth: catalogItem.depth,
            height: catalogItem.height,
            modelName: catalogItem.modelFileName
        )
        layout.furnitures.append(placed)
        markLayoutChanged()
        selectedItemID = placed.itemId
        isMovingSelectedFurniture = true
        sceneRevision += 1
        // 새 가구가 스캔 방의 벽 안/밖에 걸쳐 놓이면 방 안쪽으로 되밀어 넣는다.
        pendingWallResolveItemID = placed.itemId
    }

    /// 선택된 항목의 Y 회전을 절대 각도(도)로 설정합니다. 스톱 근처면 스냅합니다.
    /// 슬라이더 연속 조작이라 전체 리빌드 없이 노드만 갱신되도록 sceneRevision은 올리지 않습니다.
    func setSelectedRotation(degrees: Double) {
        guard let item = selectedFurniture, !Self.isWallInfill(item),
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
        let snapped = Self.snapRotation(degrees)
        guard layout.furnitures[index].rotation.y != snapped * .pi / 180 else { return }
        recordHistoryStep()
        layout.furnitures[index].rotation.y = snapped * .pi / 180
        markLayoutChanged()
    }

    /// 현재 선택 항목의 Y 회전(도, 정수 반올림).
    var selectedRotationDegrees: Double {
        guard let item = selectedFurniture else { return 0 }
        return (item.rotation.y * 180 / .pi).rounded()
    }

    static func snapRotation(_ value: Double) -> Double {
        let nearest = rotationStops.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
        return abs(nearest - value) <= 4 ? nearest : value
    }

    // MARK: - 참조(문/창문)·벽 메우기 판별

    /// 벽 메우기 패널을 나타내는 modelName 마커. 렌더러는 이 값을 보고 GLB 대신 벽 색 박스를 세운다.
    static let wallInfillModelName = "__wall_infill"

    static func isWallInfill(_ furniture: PlacedFurniture) -> Bool {
        furniture.modelName == wallInfillModelName
    }

    /// 문/창문(벽 참조)인지. 씬의 판별과 동일하게 이름/모델명 기반으로 본다.
    static func isReference(_ furniture: PlacedFurniture) -> Bool {
        isDoorOrWindowName(furniture.furnitureName) || isDoorOrWindowName(furniture.modelName)
    }

    static func isDoorOrWindowName(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.localizedCaseInsensitiveContains("door") ||
            name.localizedCaseInsensitiveContains("window") ||
            name.localizedCaseInsensitiveContains("문") ||
            name.localizedCaseInsensitiveContains("창문")
    }

    /// 선택 항목이 문/창문인지 — 제거 시 '개구부로 남기기 / 벽으로 메우기' 선택을 띄웁니다.
    var selectedIsReference: Bool {
        guard let item = selectedFurniture else { return false }
        return Self.isReference(item)
    }

    /// 선택 항목이 벽 메우기 패널인지 — 벽이므로 이동/회전/교체는 막고 제거(개구부로 되돌리기)만 허용합니다.
    var selectedIsWallInfill: Bool {
        guard let item = selectedFurniture else { return false }
        return Self.isWallInfill(item)
    }

    /// 씬이 방 메시에서 찾아낸 실제 바닥 높이(월드 Y)를 적용합니다.
    /// 높이 슬라이더의 0점, 새 가구 배치 높이가 이 값을 기준으로 합니다.
    func adoptFloorY(_ y: Double) {
        floorY = y
    }

    // MARK: - 높이(수직) 조정 — 프런트엔드 setSelectedElevationCm 대응

    /// 선택 가구를 바닥에서 띄운 높이(cm). 바닥에 놓이면 0.
    var selectedElevationCm: Double {
        guard let item = selectedFurniture else { return 0 }
        return ((item.position.y - floorY) * 100).rounded()
    }

    /// 높이 슬라이더 최댓값(cm) — 가구 윗면이 천장에 닿기 직전. 문/창문·벽 패널은 대상 아님.
    var selectedMaxElevationCm: Double {
        guard selectedSupportsElevation, let item = selectedFurniture else { return 0 }
        let ceiling = layout.space?.ceilingHeight ?? 2.4
        let height = item.height ?? 0.5
        return max(0, ((ceiling - height) * 100).rounded())
    }

    /// 선택 가구가 높이 조정 대상인지(일반 가구만 — 문/창문·벽 패널 제외).
    var selectedSupportsElevation: Bool {
        guard let item = selectedFurniture else { return false }
        return !Self.isReference(item) && !Self.isWallInfill(item)
    }

    /// 바닥에서 띄운 높이(cm)를 절대값으로 지정합니다. 0~천장 범위로 clamp.
    /// 슬라이더 연속 조작이라 전체 리빌드 없이 노드만 갱신되도록 sceneRevision은 올리지 않습니다.
    func setSelectedElevation(cm: Double) {
        guard selectedSupportsElevation,
              let item = selectedFurniture,
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
        let clamped = min(max(cm, 0), selectedMaxElevationCm)
        guard layout.furnitures[index].position.y != floorY + clamped / 100 else { return }
        recordHistoryStep()
        layout.furnitures[index].position.y = floorY + clamped / 100
        markLayoutChanged()
    }

    // MARK: - 가구 크기 조절 (웹 "크기 설정" 모달 대응 — 배치 후 선택 카드에서 조절)

    /// 크기 조절 슬라이더 범위(cm). 웹 모달은 1~1000이지만 모바일 슬라이더에선
    /// 실용 범위로 좁힌다. (10cm 미만은 조작 불가 수준, 4m 초과 가구는 비현실적)
    static let furnitureSizeRangeCm = 10.0...400.0

    /// 크기 조절 대상인지 — 일반 가구만. 문/창문은 벽 개구부 크기와 묶여 있고,
    /// 벽 패널은 벽 구조라 제외한다. (높이 띄우기와 같은 규칙)
    var selectedSupportsResize: Bool { selectedSupportsElevation }

    /// 선택 가구의 크기(cm) — 가장 긴 변 기준. 피규어 크기 슬라이더와 같은 의미 체계.
    var selectedSizeCm: Double {
        guard let item = selectedFurniture else { return 0 }
        let maxSide = max(item.width ?? 0.5, item.depth ?? 0.5, item.height ?? 0.5)
        return (maxSide * 100).rounded()
    }

    /// 가장 긴 변을 cm로 지정하면 세 축을 **같은 비율로** 함께 조절한다(찌그러짐 방지).
    /// 슬라이더 연속 조작이라 씬 리빌드 없이 노드 스케일만 갱신되도록
    /// sceneRevision은 올리지 않는다(씬의 syncSelectedSize가 반영).
    func setSelectedSize(cm: Double) {
        guard selectedSupportsResize,
              let item = selectedFurniture,
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
        let width = item.width ?? 0.5
        let depth = item.depth ?? 0.5
        let height = item.height ?? 0.5
        let maxSide = max(width, depth, height)
        guard maxSide > 0 else { return }
        let clamped = min(max(cm, Self.furnitureSizeRangeCm.lowerBound), Self.furnitureSizeRangeCm.upperBound)
        let ratio = clamped / 100 / maxSide
        guard abs(ratio - 1) > 0.000_001 else { return }
        recordHistoryStep()
        layout.furnitures[index].width = width * ratio
        layout.furnitures[index].depth = depth * ratio
        layout.furnitures[index].height = height * ratio
        markLayoutChanged()
    }

    /// 크기 슬라이더 조작이 끝났을 때: 커진 발자국이 벽을 뚫었으면 방 안쪽으로 되민다.
    func finishSelectedSizeAdjust() {
        guard let selectedItemID else { return }
        pendingWallResolveItemID = selectedItemID
    }

    // MARK: - 책장 꾸미기 (피규어 올려놓기) — 프런트엔드 서랍장 꾸미기 대응

    /// 꾸미기를 지원하는 가구인지. 프런트엔드는 GLB가 editable_furniture 폴더에 있는지로
    /// 판정하는데, 앱 번들은 리소스가 평탄화되므로 파일명의 "editable_" 접두사로 대응한다.
    static func isDecoratable(_ furniture: PlacedFurniture) -> Bool {
        furniture.modelName?.hasPrefix("editable_") == true
    }

    var selectedIsDecoratable: Bool {
        guard let item = selectedFurniture else { return false }
        return Self.isDecoratable(item)
    }

    /// 피규어의 최초 배치 시 최대 변 길이(m). 프런트엔드 FIGURE_MAX_DIMENSION 대응.
    static let figureMaxDimension = 0.35
    /// 크기 슬라이더 범위(cm). 프런트엔드 FIGURE_MIN/MAX_SIZE_CM 대응.
    static let figureSizeRangeCm = 5.0...50.0

    var isDecorating: Bool { decoratingItemID != nil }

    var decoratingFurniture: PlacedFurniture? {
        guard let decoratingItemID else { return nil }
        return layout.furnitures.first { $0.itemId == decoratingItemID }
    }

    /// 선택한 책장의 꾸미기 모드로 진입한다. 일반 선택/측정 상태는 정리한다.
    func beginDecorating() {
        guard let item = selectedFurniture, Self.isDecoratable(item) else { return }
        decoratingItemID = item.itemId
        decorShelfLevels = Self.fallbackDecorShelfLevels(for: item)
        selectedItemID = nil
        isMovingSelectedFurniture = false
        isMeasuring = false
        pendingFigure = nil
        selectedDecorID = nil
        statusMessage = nil
    }

    func endDecorating() {
        decoratingItemID = nil
        decorShelfLevels = []
        pendingFigure = nil
        selectedDecorID = nil
        statusMessage = nil
    }

    /// 카탈로그 치수를 피규어 크기로 정규화(최대 변 0.35m). 프런트 figureDimensionsFromCatalog 대응.
    static func figureDimensions(for item: FurnitureCatalogItem) -> (width: Double, height: Double, depth: Double) {
        let width = max(item.width, 0.02)
        let height = max(item.height, 0.02)
        let depth = max(item.depth, 0.02)
        let maxSide = max(width, height, depth)
        guard maxSide > figureMaxDimension else { return (width, height, depth) }
        let scale = figureMaxDimension / maxSide
        return (width * scale, height * scale, depth * scale)
    }

    /// 꾸미기 책장에 올릴 수 있는 카탈로그 항목. 사용자 생성 여부와 관계없이 저장된
    /// 카테고리가 `figure`인 피규어·소품만 허용한다.
    static func isDecorFigure(_ item: FurnitureCatalogItem) -> Bool {
        item.category.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("figure") == .orderedSame
    }

    /// 꾸미기 카탈로그에서 피규어를 선택해 선반 직접 탭 배치를 준비한다.
    func prepareDecorPlacement(_ item: FurnitureCatalogItem) {
        guard isDecorating else { return }
        guard Self.isDecorFigure(item) else {
            pendingFigure = nil
            statusMessage = "꾸미기 책장에는 피규어만 올릴 수 있어요"
            return
        }
        selectedDecorID = nil
        pendingFigure = item
        statusMessage = "피규어를 놓을 선반의 윗면을 탭하세요"
    }

    /// 씬이 찾은 선반 표면 지점(부모 로컬 좌표)에 대기 중인 피규어를 올려놓는다.
    func placePendingFigure(atLocal position: FurnitureTransform.Vector3) {
        guard let decoratingItemID, let pendingFigure,
              let index = layout.furnitures.firstIndex(where: { $0.itemId == decoratingItemID }) else { return }
        guard Self.isDecorFigure(pendingFigure) else {
            self.pendingFigure = nil
            statusMessage = "꾸미기 책장에는 피규어만 올릴 수 있어요"
            return
        }
        recordHistoryStep()
        let dims = Self.figureDimensions(for: pendingFigure)
        let safePosition = clampedDecorPosition(
            position,
            itemWidth: dims.width,
            itemDepth: dims.depth,
            scale: 1,
            furniture: layout.furnitures[index]
        )
        let decoration = PlacedDecoration(
            decorId: nextDecorID,
            name: pendingFigure.name,
            modelName: pendingFigure.modelFileName,
            width: dims.width,
            height: dims.height,
            depth: dims.depth,
            position: safePosition,
            rotationY: 0,
            scale: 1
        )
        nextDecorID += 1
        layout.furnitures[index].decorations = (layout.furnitures[index].decorations ?? []) + [decoration]
        markLayoutChanged()
        self.pendingFigure = nil
        selectedDecorID = decoration.decorId
        statusMessage = nil
        sceneRevision += 1
        Haptics.impact(.light)
    }

    /// 3D 선반 탭 대신 메뉴에서 선택한 선반 중앙에 대기 중인 피규어를 배치한다.
    func placePendingFigure(on shelf: DecorShelfLevel) {
        guard decorShelfLevels.contains(where: { $0.id == shelf.id }) else { return }
        placePendingFigure(atLocal: .init(x: 0, y: shelf.height, z: 0))
    }

    /// 선택된 피규어를 다른 선반 지점(부모 로컬 좌표)으로 옮긴다.
    func moveSelectedDecor(toLocal position: FurnitureTransform.Vector3) {
        guard let indices = selectedDecorIndices() else { return }
        guard let decoration = layout.furnitures[indices.furniture].decorations?[indices.decor] else { return }
        let safePosition = clampedDecorPosition(
            position,
            itemWidth: decoration.width,
            itemDepth: decoration.depth,
            scale: decoration.scale,
            furniture: layout.furnitures[indices.furniture]
        )
        guard decoration.position != safePosition else { return }
        recordHistoryStep()
        layout.furnitures[indices.furniture].decorations?[indices.decor].position = safePosition
        markLayoutChanged()
        statusMessage = nil
        sceneRevision += 1
    }

    /// 선택한 피규어를 책장 로컬 좌표 기준으로 조금씩 이동한다.
    func nudgeSelectedDecor(deltaX: Double, deltaZ: Double) {
        guard deltaX.isFinite, deltaZ.isFinite,
              let decoration = selectedDecoration else { return }
        moveSelectedDecor(
            toLocal: .init(
                x: decoration.position.x + deltaX,
                y: decoration.position.y,
                z: decoration.position.z + deltaZ
            )
        )
    }

    /// 현재 가로·앞뒤 위치를 유지한 채 메뉴에서 고른 다른 선반으로 이동한다.
    func moveSelectedDecor(to shelf: DecorShelfLevel) {
        guard decorShelfLevels.contains(where: { $0.id == shelf.id }),
              let decoration = selectedDecoration else { return }
        moveSelectedDecor(
            toLocal: .init(
                x: decoration.position.x,
                y: shelf.height,
                z: decoration.position.z
            )
        )
    }

    /// SceneKit이 실제 위쪽 면을 찾은 뒤 기본 3단 목록을 모델의 실제 선반 높이로 교체한다.
    func updateDecorShelfHeights(_ heights: [Double]) {
        guard isDecorating else { return }
        let resolved = Self.makeDecorShelfLevels(from: heights)
        guard !resolved.isEmpty, resolved != decorShelfLevels else { return }
        decorShelfLevels = resolved
    }

    static func makeDecorShelfLevels(from heights: [Double]) -> [DecorShelfLevel] {
        let sorted = heights
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()
        var unique: [Double] = []
        for height in sorted where unique.last.map({ height - $0 >= 0.12 }) ?? true {
            unique.append(height)
        }

        return unique.enumerated().map { index, height in
            DecorShelfLevel(
                id: index,
                title: decorShelfTitle(index: index, count: unique.count),
                height: height
            )
        }
    }

    private static func fallbackDecorShelfLevels(for furniture: PlacedFurniture) -> [DecorShelfLevel] {
        let height = max((furniture.height ?? 1.8) * max(furniture.scale.y, 0.001), 0.3)
        return makeDecorShelfLevels(from: [height / 3, height * 2 / 3, height])
    }

    private static func decorShelfTitle(index: Int, count: Int) -> String {
        switch (count, index) {
        case (1, _): "선반"
        case (2, 0): "아래 선반"
        case (2, _): "위 선반"
        case (3, 0): "아래 선반"
        case (3, 1): "가운데 선반"
        case (3, _): "위 선반"
        default: "\(index + 1)단 선반"
        }
    }

    /// 드래그 중인 소품의 후보 위치를 책장 안쪽으로 제한한다. SceneKit 노드는 손가락을
    /// 실시간으로 따라가고, 드래그 종료 시 `moveSelectedDecor`가 최종 위치를 한 번만 저장한다.
    func constrainedSelectedDecorPosition(
        _ position: FurnitureTransform.Vector3
    ) -> FurnitureTransform.Vector3? {
        guard let indices = selectedDecorIndices(),
              let decoration = layout.furnitures[indices.furniture].decorations?[indices.decor] else { return nil }
        return clampedDecorPosition(
            position,
            itemWidth: decoration.width,
            itemDepth: decoration.depth,
            scale: decoration.scale,
            furniture: layout.furnitures[indices.furniture]
        )
    }

    /// 프런트엔드 `replaceSelectedFigure` 대응. 현재 소품의 지지점과 회전은 유지하고,
    /// 카탈로그 모델과 기본 소품 크기만 교체한다.
    func replaceSelectedDecor(with item: FurnitureCatalogItem) {
        guard let indices = selectedDecorIndices(),
              let current = layout.furnitures[indices.furniture].decorations?[indices.decor] else { return }
        guard Self.isDecorFigure(item) else {
            statusMessage = "꾸미기 책장에는 피규어만 올릴 수 있어요"
            return
        }
        recordHistoryStep()
        let dimensions = Self.figureDimensions(for: item)
        let position = clampedDecorPosition(
            current.position,
            itemWidth: dimensions.width,
            itemDepth: dimensions.depth,
            scale: 1,
            furniture: layout.furnitures[indices.furniture]
        )
        layout.furnitures[indices.furniture].decorations?[indices.decor] = PlacedDecoration(
            decorId: current.decorId,
            name: item.name,
            modelName: item.modelFileName,
            width: dimensions.width,
            height: dimensions.height,
            depth: dimensions.depth,
            position: position,
            rotationY: current.rotationY,
            scale: 1
        )
        markLayoutChanged()
        statusMessage = nil
        sceneRevision += 1
        Haptics.impact(.light)
    }

    private func clampedDecorPosition(
        _ position: FurnitureTransform.Vector3,
        itemWidth: Double,
        itemDepth: Double,
        scale: Double,
        furniture: PlacedFurniture
    ) -> FurnitureTransform.Vector3 {
        // 회전된 소품도 밖으로 나가지 않도록 두 수평 축 중 큰 쪽을 안전 여백으로 쓴다.
        let footprintRadius = max(itemWidth, itemDepth) * max(scale, 0.001) / 2
        let maxX = max((furniture.width ?? 0.8) / 2 - footprintRadius - 0.015, 0)
        let maxZ = max((furniture.depth ?? 0.3) / 2 - footprintRadius - 0.015, 0)
        return .init(
            x: min(max(position.x, -maxX), maxX),
            y: position.y,
            z: min(max(position.z, -maxZ), maxZ)
        )
    }

    var selectedDecoration: PlacedDecoration? {
        guard let indices = selectedDecorIndices() else { return nil }
        return layout.furnitures[indices.furniture].decorations?[indices.decor]
    }

    var selectedDecorRotationDegrees: Double {
        guard let decoration = selectedDecoration else { return 0 }
        return (decoration.rotationY * 180 / .pi).rounded()
    }

    /// 피규어 Y 회전(도). 슬라이더 연속 조작이라 씬 리빌드 없이 노드만 갱신되도록 revision은 올리지 않는다.
    func setSelectedDecorRotation(degrees: Double) {
        guard let indices = selectedDecorIndices() else { return }
        let snapped = Self.snapRotation(degrees)
        guard layout.furnitures[indices.furniture].decorations?[indices.decor].rotationY != snapped * .pi / 180 else { return }
        recordHistoryStep()
        layout.furnitures[indices.furniture].decorations?[indices.decor].rotationY = snapped * .pi / 180
        markLayoutChanged()
    }

    /// 피규어 표시 크기(cm) = 기준 최대 변 × 균일 스케일. 프런트 figureSizeCmForObject 대응.
    var selectedDecorSizeCm: Double {
        guard let decoration = selectedDecoration else { return 0 }
        let maxSide = max(decoration.width, decoration.height, decoration.depth)
        return (maxSide * decoration.scale * 100).rounded()
    }

    /// 선택 카드와 VoiceOver가 함께 사용하는 현재 선반·위치·크기 설명.
    var selectedDecorAccessibilitySummary: String {
        guard let decoration = selectedDecoration else { return "선택된 피규어가 없습니다" }
        let shelf = decorShelfLevels.min(by: {
            abs($0.height - decoration.position.y) < abs($1.height - decoration.position.y)
        })?.title ?? "높이 \(centimeters(decoration.position.y))센티미터"
        return [
            shelf,
            horizontalPositionDescription(decoration.position.x),
            depthPositionDescription(decoration.position.z),
            "크기 \(Int(selectedDecorSizeCm))센티미터"
        ].joined(separator: ", ")
    }

    private func horizontalPositionDescription(_ x: Double) -> String {
        let value = centimeters(abs(x))
        if value < 1 { return "가로 중앙" }
        return x < 0 ? "왼쪽 \(value)센티미터" : "오른쪽 \(value)센티미터"
    }

    private func depthPositionDescription(_ z: Double) -> String {
        let value = centimeters(abs(z))
        if value < 1 { return "앞뒤 중앙" }
        // 꾸미기 전용 책장의 열린 정면은 로컬 +Z 방향이다.
        return z > 0 ? "앞쪽 \(value)센티미터" : "뒤쪽 \(value)센티미터"
    }

    private func centimeters(_ meters: Double) -> Int {
        Int((meters * 100).rounded())
    }

    func setSelectedDecorSize(cm: Double) {
        guard let indices = selectedDecorIndices(),
              let decoration = layout.furnitures[indices.furniture].decorations?[indices.decor] else { return }
        let maxSide = max(decoration.width, decoration.height, decoration.depth)
        guard maxSide > 0 else { return }
        let clamped = min(max(cm, Self.figureSizeRangeCm.lowerBound), Self.figureSizeRangeCm.upperBound)
        let scale = clamped / 100 / maxSide
        guard decoration.scale != scale else { return }
        recordHistoryStep()
        layout.furnitures[indices.furniture].decorations?[indices.decor].scale = scale
        markLayoutChanged()
    }

    func deleteSelectedDecor() {
        guard let indices = selectedDecorIndices() else { return }
        recordHistoryStep()
        layout.furnitures[indices.furniture].decorations?.remove(at: indices.decor)
        markLayoutChanged()
        selectedDecorID = nil
        sceneRevision += 1
    }

    private func selectedDecorIndices() -> (furniture: Int, decor: Int)? {
        guard let decoratingItemID, let selectedDecorID,
              let furnitureIndex = layout.furnitures.firstIndex(where: { $0.itemId == decoratingItemID }),
              let decorIndex = layout.furnitures[furnitureIndex].decorations?
                  .firstIndex(where: { $0.decorId == selectedDecorID }) else { return nil }
        return (furnitureIndex, decorIndex)
    }

    /// 벽 색상 변경(4종 팝오버). 씬을 다시 지어 벽/배경에 반영합니다.
    func setWallColor(_ hex: String) {
        guard layout.space?.wallColor.caseInsensitiveCompare(hex) != .orderedSame else { return }
        recordHistoryStep()
        layout.space?.wallColor = hex
        markLayoutChanged()
        sceneRevision += 1
    }

    var wallColorHex: String { layout.space?.wallColor ?? "#F2EDE5" }

    /// 프런트엔드 FLOOR_COLORS 선택값. nil이면 스캔 원본 바닥 재질을 유지합니다.
    var floorColorHex: String? { layout.space?.floorColor }

    func setFloorColor(_ hex: String) {
        guard layout.space?.floorColor?.caseInsensitiveCompare(hex) != .orderedSame else { return }
        recordHistoryStep()
        layout.space?.floorColor = hex
        markLayoutChanged()
        // 스캔 방은 바닥 mesh만 증분 tint하고, 박스 방은 바닥을 다시 만듭니다.
        sceneRevision += 1
    }

    /// 뷰 모드를 직접 지정(Skyview/사람 뷰 토글).
    func setViewMode(_ mode: RoomViewMode) {
        guard viewMode != mode else { return }
        viewMode = mode
        if mode == .person {
            selectedItemID = nil
            isMovingSelectedFurniture = false
            isMeasuring = false
        }
    }

    var isSkyview: Bool { viewMode == .skyView }
    var isPersonView: Bool { viewMode == .person }

    func replaceSelected(with furniture: FurnitureDetail) {
        guard let item = selectedFurniture, !Self.isWallInfill(item),
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
        recordHistoryStep()
        layout.furnitures[index].furnitureId = furniture.furnitureId
        layout.furnitures[index].furnitureName = furniture.name
        layout.furnitures[index].width = furniture.width
        layout.furnitures[index].depth = furniture.depth
        layout.furnitures[index].height = furniture.height
        // 렌더러는 modelName으로 GLB를 고르므로, 이걸 갱신하지 않으면 치수만 바뀌고
        // 모델은 그대로 남는다(책상 → 침대 크기의 책상). 카탈로그가 준 파일명을 우선 쓰고,
        // 없으면 새 이름으로 카테고리 기본 모델을 찾는다.
        layout.furnitures[index].modelName = furniture.modelName
            ?? FurnitureCatalog.defaultModelName(matching: furniture.name)
            ?? layout.furnitures[index].modelName
        // 꾸미기 책장을 다른 가구로 교체하면 새 모델엔 선반이 없으므로 피규어는 함께 삭제(웹과 동일).
        layout.furnitures[index].decorations = nil
        markLayoutChanged()
        // 벽에 붙어 있던 가구가 더 큰 가구로 바뀌면 새 발자국이 벽을 뚫는다. 씬에 되밀기를 요청.
        pendingWallResolveItemID = item.itemId
        sceneRevision += 1
    }

    func deleteSelected() {
        guard let selectedItemID else { return }
        recordHistoryStep()
        layout.furnitures.removeAll { $0.itemId == selectedItemID }
        markLayoutChanged()
        self.selectedItemID = nil
        isMovingSelectedFurniture = false
        sceneRevision += 1
    }

    /// 선택된 문/창문을 벽으로 메웁니다(개구부 채우기). 프런트엔드 `deleteSelectedReference(true)` 대응.
    /// 문/창문을 제거하고 그 자리에 같은 크기·자세의 벽 색 패널을 세워 구멍을 막습니다.
    /// (`deleteSelected()`가 프런트엔드의 `deleteSelectedReference(false)` = 개구부로 남기기에 해당)
    func fillOpeningWithWall() {
        guard let item = selectedFurniture, Self.isReference(item),
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
        recordHistoryStep()
        let infill = PlacedFurniture(
            itemId: takeLocalItemID(),
            furnitureId: 0,
            furnitureName: "벽",
            position: item.position,
            rotation: item.rotation,
            scale: item.scale,
            width: item.width,
            depth: max(item.depth ?? 0.1, 0.1),
            height: item.height,
            modelName: Self.wallInfillModelName
        )
        layout.furnitures.remove(at: index)
        layout.furnitures.append(infill)
        markLayoutChanged()
        selectedItemID = nil
        isMovingSelectedFurniture = false
        sceneRevision += 1
    }

    func toggleViewMode() {
        viewMode = viewMode == .threeD ? .skyView : .threeD
    }

    /// 서버 metadata JSON 인코딩용. 로더는 `editedObjects`를 우선 읽으므로 나머지는 비워 둔다.
    private struct ExportedRoomMetadata: Encodable {
        var objects: [EditableScanItem] = []
        var doors: [EditableScanItem] = []
        var windows: [EditableScanItem] = []
        var openings: [EditableScanItem] = []
        var floorColor: String?
        var editedObjects: [EditableScanItem]

        enum CodingKeys: String, CodingKey {
            case objects, doors, windows, openings, editedObjects
            case floorColor = "_spatiumFloorColor"
        }
    }

    /// 서버에 저장된 룸인지(= 업로드 완료되어 projectID + 서버 roomID가 있는지).
    private var isServerRoom: Bool {
        guard projectID != nil else { return false }
        return !roomID.hasPrefix("local")
    }

    /// 게스트(비로그인)가 만든 로컬 프로젝트의 룸인지. 서버 프로젝트가 없으므로
    /// 편집 내용을 서버에 저장할 수 없다 — 저장 버튼을 막고 로그인 안내를 보여준다.
    var isGuestLocalProject: Bool {
        projectID?.hasPrefix("local-") == true
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }

        guard let projectID else {
            // 프로젝트 없이 연 룸(테스트 스캔 등)은 업로드할 곳이 없다.
            statusMessage = "프로젝트가 없어 서버에 저장할 수 없어요."
            return
        }

        // 게스트 로컬 프로젝트: 서버에 프로젝트가 없어 업로드가 반드시 실패한다.
        // 기술적 에러("서버에 연결할 수 없습니다") 대신 할 수 있는 일을 안내한다.
        // (저장 버튼도 비활성화되지만, 다른 경로로 호출돼도 안전하게 막는다)
        if projectID.hasPrefix("local-") {
            statusMessage = "게스트 프로젝트는 서버에 저장할 수 없어요. 로그인 후 이용해 주세요."
            return
        }

        // 폴백(기본) 에디터: 원본 씬/메타데이터를 받지 못한 채 열렸다. 이 상태로 저장하면
        // 빈 editedObjects가 서버의 기존 메타데이터를 통째로 덮어쓰므로 저장을 차단한다.
        if loadsRemoteLayout && !remoteLayoutLoaded {
            statusMessage = "방 데이터를 불러오지 못해 저장할 수 없어요. 방을 다시 열어 주세요."
            return
        }

        do {
            let metadataURL = try exportEditedMetadata()
            defer { try? FileManager.default.removeItem(at: metadataURL) }

            if !isServerRoom {
                // 아직 업로드 안 된 스캔: 안내만 하지 않고 지금 파일(USDZ + 메타데이터)을
                // 서버로 올려 룸을 만든다. 이후 저장부터는 일반 서버 룸으로 동작한다.
                guard let usdzURL else {
                    statusMessage = "업로드할 스캔 파일(USDZ)이 없어요."
                    return
                }
                statusMessage = "스캔을 서버에 업로드하는 중..."
                let created = try await ProjectService().createRoom(
                    projectID: projectID,
                    roomName: layout.roomName,
                    metadataURL: metadataURL,
                    usdzURL: usdzURL
                )
                let localDraftURL = draftFileURL
                roomID = created.id
                layout.roomId = created.id
                draftFileName = Self.makeDraftFileName(
                    projectID: projectID,
                    roomID: created.id,
                    roomName: layout.roomName
                )
                try? FileManager.default.removeItem(at: localDraftURL)
                isOffline = false
                markCurrentLayoutSaved()
                statusMessage = "스캔이 업로드되어 저장되었습니다."
                onServerRoomCreated?(created)
                return
            }

            try await ProjectService().saveEditedRoom(
                projectID: projectID,
                roomID: roomID,
                area: layout.space?.area,
                metadataURL: metadataURL
            )
            // 서버 메타데이터가 바뀌었으므로 로컬 스캔 캐시를 비워, 방 목록의 항목 수와
            // 다음 렌더가 최신 편집 상태를 반영하게 한다.
            RoomScanAssetService().invalidateCache(forRoomID: roomID)
            markCurrentLayoutSaved()
            statusMessage = "저장되었습니다."
        } catch {
            statusMessage = "저장 실패: \(error.localizedDescription)"
        }
    }

    /// 현재 편집된 가구 배치를 서버 metadata(JSON)로 내보낸다.
    /// 로더(RoomPlanExportJSON)가 `editedObjects`를 우선 읽으므로 그대로 복원된다.
    private func exportEditedMetadata() throws -> URL {
        let editedObjects: [EditableScanItem] = layout.furnitures.map { f in
            let width = f.width ?? 0.5
            let height = f.height ?? 0.5
            let depth = f.depth ?? 0.5
            var item = EditableScanItem(userAddedNamed: f.furnitureName, width: width, height: height, depth: depth)
            item.detectedCategory = f.furnitureName
            item.positionX = f.position.x
            // 편집기는 바닥면 기준 y를 쓰므로 중심 높이로 되돌려 저장(로더가 다시 -height/2 함).
            item.positionY = f.position.y + height / 2
            item.positionZ = f.position.z
            item.detectedRotationY = f.rotation.y
            item.rotationY = 0
            item.modelName = f.modelName
            // 책장 위 피규어(부모 로컬 transform)도 함께 저장해 다음에 열 때 복원한다.
            item.decorations = (f.decorations?.isEmpty == false) ? f.decorations : nil
            return item
        }

        let metadata = ExportedRoomMetadata(
            floorColor: layout.space?.floorColor,
            editedObjects: editedObjects
        )
        let data = try JSONEncoder.prettyPrinted.encode(metadata)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("edited-room-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func takeLocalItemID() -> Int {
        defer { nextLocalItemID -= 1 }
        return nextLocalItemID
    }
}
