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
    @Published var hasUnsavedChanges = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var hasRecoverableDraft = false
    @Published var recoverableDraftSavedAt: Date?
    @Published var draftSaveState: EditorDraftSaveState = .idle
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
    @Published var decorShelfLevels: [DecorShelfLevel] = []
    var nextDecorID = 1

    /// 회전 슬라이더가 스냅되는 각도 스톱(도).
    static let rotationStops: [Double] = [-180, -90, 0, 90, 180]
    /// 접근성 이동 버튼 한 번에 움직이는 거리(m).
    static let decorNudgeStep = 0.05
    /// 벽 메우기 패널을 나타내는 modelName 마커.
    static let wallInfillModelName = "__wall_infill"
    /// 일반 가구 크기 조절 범위(cm).
    static let furnitureSizeRangeCm = 10.0...400.0
    /// 피규어 최초 배치 최대 변과 편집 가능한 표시 크기 범위.
    static let figureMaxDimension = 0.35
    static let figureSizeRangeCm = 5.0...50.0

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
    var nextLocalItemID = -1
    /// 새 가구가 앉을 바닥 높이(월드 Y). 박스 방은 0, 스캔 방은 감지 가구 바닥에서 유도.
    var floorY: Double = 0

    struct EditorSnapshot {
        var layout: RoomLayout
        var selectedItemID: Int?
        var decoratingItemID: Int?
        var selectedDecorID: Int?
        var isMovingSelectedFurniture: Bool
    }

    static let historyLimit = 30
    static let draftSaveFailureMessage = "이 기기에 임시 저장하지 못했어요. 저장 공간을 확인한 후 다시 시도해 주세요."
    var undoHistory: [EditorSnapshot] = []
    var redoHistory: [EditorSnapshot] = []
    var historyTransactionStart: EditorSnapshot?
    var savedLayout: RoomLayout
    var pendingRecoverableDraft: EditorDraft?
    var draftSaveTask: Task<Void, Never>?
    let draftDirectoryURL: URL
    let draftDiskStore: RoomEditorDraftDiskStore
    var draftFileName: String
    var draftOperationRevision: UInt64 = 0

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
        draftDirectoryURL: URL? = nil,
        draftOperationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.roomID = room.id
        self.projectID = projectID
        self.projectName = projectName
        self.usdzURL = nil
        self.loadsRemoteLayout = true
        let draftDirectoryURL = draftDirectoryURL ?? Self.defaultDraftDirectoryURL()
        self.draftDirectoryURL = draftDirectoryURL
        self.draftDiskStore = RoomEditorDraftDiskStore(
            directoryURL: draftDirectoryURL,
            operationObserver: draftOperationObserver
        )
        Self.clearDraftDirectoryForUITestingIfRequested(self.draftDirectoryURL)
        self.draftFileName = Self.makeDraftFileName(
            projectID: projectID,
            roomID: room.id,
            roomName: room.roomType
        )
        let initialLayout = RoomLayout(
            roomId: room.id,
            roomName: room.roomType,
            viewMode: .threeD,
            space: RoomSpace(
                spaceId: room.id,
                name: room.roomType,
                area: room.area ?? 16,
                ceilingHeight: 2.4
            ),
            furnitures: []
        )
        self.layout = initialLayout
        self.savedLayout = initialLayout
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
        draftDirectoryURL: URL? = nil,
        draftOperationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.roomID = roomID ?? "local-scan"
        self.projectID = projectID
        self.projectName = projectName
        self.usdzURL = usdzURL
        self.loadsRemoteLayout = false
        let draftDirectoryURL = draftDirectoryURL ?? Self.defaultDraftDirectoryURL()
        self.draftDirectoryURL = draftDirectoryURL
        self.draftDiskStore = RoomEditorDraftDiskStore(
            directoryURL: draftDirectoryURL,
            operationObserver: draftOperationObserver
        )
        Self.clearDraftDirectoryForUITestingIfRequested(self.draftDirectoryURL)
        self.draftFileName = Self.makeDraftFileName(
            projectID: projectID,
            roomID: roomID ?? "local-scan",
            roomName: roomName
        )
        // 서버 룸(projectID 있음)을 씬으로 열면 온라인 저장이 가능하므로 오프라인 표시하지 않는다.
        self.isOffline = (projectID == nil)
        var initialLayout = RoomLayout(
            roomId: roomID ?? "local-scan",
            roomName: roomName,
            viewMode: .threeD,
            space: RoomSpace(
                spaceId: roomID ?? "local-scan",
                name: roomName,
                area: max(area, 4),
                ceilingHeight: ceilingHeight,
                floorColor: initialFloorColor
            ),
            furnitures: []
        )
        // 문/창문도 모델이 있으므로 별도 렌더 대상으로 올립니다. 개구부는 열린 공간이라 제외합니다.
        var nextID = -1
        initialLayout.furnitures = scanItems.filter { $0.sourceType != "개구부" }.map { item in
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
        self.layout = initialLayout
        self.savedLayout = initialLayout
        self.nextLocalItemID = nextID
        // 저장된 피규어 decorId와 새로 올릴 피규어 id가 겹치지 않게 이어서 발급한다.
        self.nextDecorID = (initialLayout.furnitures
            .compactMap { $0.decorations?.map(\.decorId).max() }
            .max() ?? 0) + 1
        // 감지된 가구들의 바닥면(= 스캔 바닥 높이)을 새 가구 배치 기준으로 삼습니다.
        // 씬이 방 메시에서 실제 바닥을 찾으면 adoptFloorY로 이 값을 교정합니다.
        // (가구를 모두 띄워 저장한 방에서 띄운 높이가 새 바닥으로 굳는 것 방지)
        // 벽 밀착/충돌은 씬(RoomEditorSceneView)의 벽 시스템이 렌더·드래그 모두에서 일관되게 처리합니다.
        self.floorY = initialLayout.furnitures.map { $0.position.y }.min() ?? 0

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

    func loadLayout() async {
        // 스캔에서 바로 연 편집기는 실제 스캔 메시 + 감지 가구로 이미 구성돼 있으니 서버 조회를 건너뜁니다.
        guard loadsRemoteLayout else {
            sceneRevision += 1
            await inspectRecoverableDraft()
            return
        }
        // 백엔드에는 별도 레이아웃 조회 API가 없다. 서버 룸의 실제 배치는 scene(metadata)
        // 응답으로 여는 씬 에디터가 담당하고, 이 경로(폴백 박스 에디터)는 방 데이터를 받지
        // 못한 상태다. 네트워크 문제처럼 보이지 않게 상태를 그대로 알려주고,
        // remoteLayoutLoaded=false 가드가 빈 레이아웃으로 서버를 덮어쓰는 저장을 막는다.
        isOffline = true
        statusMessage = "방 데이터를 불러오지 못해 이 기기에서만 편집합니다."
        sceneRevision += 1
        await inspectRecoverableDraft()
    }

    /// 측정 모드 면적 배지용 실제 바닥 면적(m²). 씬이 방 셸에서 계산해 게시한다.
    /// (프런트엔드 room-area 배지 대응 — 바닥 mesh가 없으면 폭×깊이 근사값)
    @Published private(set) var roomAreaSquareMeters: Double?

    func adoptRoomArea(_ area: Double?) {
        guard roomAreaSquareMeters != area else { return }
        roomAreaSquareMeters = area
    }

    /// 두 색상 선택값이 같은지(둘 다 nil 포함) 비교한다.
    private static func isSameSurfaceColor(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): lhs.caseInsensitiveCompare(rhs) == .orderedSame
        default: false
        }
    }

    /// 벽 색상 변경(4종 팝오버 + 기본 색상 되돌리기). 씬을 다시 지어 벽/배경에 반영합니다.
    /// 프런트엔드 applyRoomWallColor 대응 — nil이면 스캔 원본 벽 재질로 복원합니다.
    func setWallColor(_ hex: String?) {
        guard layout.space != nil,
              !Self.isSameSurfaceColor(layout.space?.wallColor, hex) else { return }
        recordHistoryStep()
        layout.space?.wallColor = hex
        markLayoutChanged()
        sceneRevision += 1
    }

    /// 사용자가 고른 벽 색. nil이면 스캔 원본 벽 재질(박스 방은 기본 벽색)을 유지합니다.
    var wallColorHex: String? { layout.space?.wallColor }

    /// 벽 메우기 패널처럼 실제 색값이 필요한 곳에서 쓰는 벽 색. (원본 유지 상태면 기본 크림색)
    var resolvedWallColorHex: String { layout.space?.wallColor ?? "#F2EDE5" }

    /// 프런트엔드 FLOOR_COLORS 선택값. nil이면 스캔 원본 바닥 재질을 유지합니다.
    var floorColorHex: String? { layout.space?.floorColor }

    /// 바닥 색상 변경. 프런트엔드 applyRoomFloorColor 대응 — nil이면 원본 재질로 복원합니다.
    func setFloorColor(_ hex: String?) {
        guard layout.space != nil,
              !Self.isSameSurfaceColor(layout.space?.floorColor, hex) else { return }
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

    func toggleViewMode() {
        viewMode = viewMode == .threeD ? .skyView : .threeD
    }

    /// 서버 metadata JSON 인코딩용. 앱 전용 `editedObjects`와 웹 전용
    /// `objects/doors/windows`를 함께 기록해 어느 편집기에서 열어도 같은 상태를 복원한다.
    private struct ExportedRoomMetadata: Encodable {
        var objects: [FrontendRoomObject] = []
        var doors: [FrontendRoomObject] = []
        var windows: [FrontendRoomObject] = []
        var openings: [FrontendRoomObject] = []
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
                await removeDraftFile(at: localDraftURL, updatesState: false)
                isOffline = false
                await markCurrentLayoutSaved()
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
            await RoomScanAssetService().invalidateCache(forRoomID: roomID)
            await markCurrentLayoutSaved()
            statusMessage = "저장되었습니다."
        } catch {
            statusMessage = "저장 실패: \(error.localizedDescription)"
        }
    }

    /// 현재 편집된 가구 배치를 서버 metadata(JSON)로 내보낸다. 앱은 `editedObjects`를
    /// 우선 읽고, 프런트엔드는 `objects/doors/windows`를 읽으므로 두 표현을 함께 기록한다.
    private func exportEditedMetadata() throws -> URL {
        let editedObjects: [EditableScanItem] = layout.furnitures.map { f in
            // 앱 전용 EditableScanItem에는 scale 필드가 없으므로 현재 표시 치수에
            // scale을 반영해 저장한다. 다시 열 때 scale 1로 복원돼도 크기는 같다.
            let width = (f.width ?? 0.5) * f.scale.x
            let height = (f.height ?? 0.5) * f.scale.y
            let depth = (f.depth ?? 0.5) * f.scale.z
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

        let windows = layout.furnitures.filter(Self.isWindowFurniture)
        let doors = layout.furnitures.filter {
            Self.isDoorOrWindowName($0.furnitureName)
                || Self.isDoorOrWindowName($0.modelName)
        }.filter { !Self.isWindowFurniture($0) }
        let referenceIDs = Set((doors + windows).map(\.itemId))
        let objects = layout.furnitures.filter { !referenceIDs.contains($0.itemId) }

        let metadata = ExportedRoomMetadata(
            objects: objects.map(FrontendRoomObject.init),
            doors: doors.map(FrontendRoomObject.init),
            windows: windows.map(FrontendRoomObject.init),
            floorColor: layout.space?.floorColor,
            editedObjects: editedObjects
        )
        let data = try JSONEncoder.prettyPrinted.encode(metadata)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("edited-room-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func isWindowFurniture(_ furniture: PlacedFurniture) -> Bool {
        [furniture.furnitureName, furniture.modelName].compactMap { $0 }
            .contains { value in
                value.localizedCaseInsensitiveContains("window")
                    || value.localizedCaseInsensitiveContains("창문")
            }
    }

}
