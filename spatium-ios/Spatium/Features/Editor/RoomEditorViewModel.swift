import Combine
import Foundation

@MainActor
final class RoomEditorViewModel: ObservableObject {
    @Published var layout: RoomLayout
    @Published var viewMode: RoomViewMode = .threeD
    @Published var selectedItemID: Int?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var isOffline = false
    /// 마지막 저장(저장하기) 이후 편집이 있었는지. 방 전환/이탈 경고에 사용합니다.
    @Published private(set) var hasUnsavedChanges = false
    /// 하단 뷰바의 "측정" 모드 on/off (프런트엔드와 동일하게 배지/치수 표시 전환).
    @Published var isMeasuring = false
    /// 선택한 가구를 드래그로 이동하는 편집 상태. 측정 모드와 분리합니다.
    @Published var isMovingSelectedFurniture = false

    /// 회전 슬라이더가 스냅되는 각도 스톱(도).
    static let rotationStops: [Double] = [-180, -90, 0, 90, 180]

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
    private let editorService = RoomEditorService()
    private var nextLocalItemID = -1
    /// 새 가구가 앉을 바닥 높이(월드 Y). 박스 방은 0, 스캔 방은 감지 가구 바닥에서 유도.
    private var floorY: Double = 0

    var selectedFurniture: PlacedFurniture? {
        guard let selectedItemID else { return nil }
        return layout.furnitures.first { $0.itemId == selectedItemID }
    }

    init(room: RoomRecord, projectID: String? = nil, projectName: String? = nil) {
        self.roomID = room.id
        self.projectID = projectID
        self.projectName = projectName
        self.usdzURL = nil
        self.loadsRemoteLayout = true
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
    }

    /// 스캔 결과로 바로 여는 3D 에디터. 실제 스캔 메시(usdzURL) 위에
    /// 감지된 객체를 편집 가능한 가구로 올려 시작합니다.
    init(scanItems: [EditableScanItem], roomName: String, usdzURL: URL?, area: Double, ceilingHeight: Double, roomID: String? = nil, projectID: String? = nil, projectName: String? = nil) {
        self.roomID = roomID ?? "local-scan"
        self.projectID = projectID
        self.projectName = projectName
        self.usdzURL = usdzURL
        self.loadsRemoteLayout = false
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
                wallColor: "#F2EDE5"
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
                modelName: item.modelName ?? FurnitureCatalog.defaultModelName(matching: "\(category) \(item.sourceType)")
            )
        }
        self.nextLocalItemID = nextID
        // 감지된 가구들의 바닥면(= 스캔 바닥 높이)을 새 가구 배치 기준으로 삼습니다.
        // 벽 밀착/충돌은 씬(RoomEditorSceneView)의 벽 시스템이 렌더·드래그 모두에서 일관되게 처리합니다.
        self.floorY = self.layout.furnitures.map { $0.position.y }.min() ?? 0

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
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            layout = try await editorService.fetchLayout(roomID: roomID)
            if let mode = layout.viewMode { viewMode = mode }
            isOffline = false
            statusMessage = nil
            sceneRevision += 1
        } catch {
            isOffline = true
            statusMessage = "서버에 연결할 수 없어 오프라인으로 편집합니다."
        }
    }

    func place(furniture: FurnitureDetail) {
        let placed = PlacedFurniture(
            itemId: takeLocalItemID(),
            furnitureId: furniture.furnitureId,
            furnitureName: furniture.name,
            position: .zero,
            rotation: .zero,
            scale: .one,
            width: furniture.width,
            depth: furniture.depth,
            height: furniture.height
        )
        layout.furnitures.append(placed)
        hasUnsavedChanges = true
        selectedItemID = placed.itemId
        isMovingSelectedFurniture = true
        sceneRevision += 1

        guard !isOffline else { return }
        Task {
            if let serverItem = try? await editorService.placeFurniture(
                roomID: roomID, furnitureID: furniture.furnitureId, transform: .identity
            ) {
                replaceLocalItemID(placed.itemId, with: serverItem.itemId)
            }
        }
    }

    func commitTransform(itemID: Int, transform: FurnitureTransform) {
        guard let index = layout.furnitures.firstIndex(where: { $0.itemId == itemID }) else { return }
        layout.furnitures[index].position = transform.position
        layout.furnitures[index].rotation = transform.rotation
        layout.furnitures[index].scale = transform.scale
        hasUnsavedChanges = true

        guard !isOffline, itemID > 0 else { return }
        Task {
            try? await editorService.updateTransform(itemID: itemID, transform: transform)
        }
    }

    func rotateSelected(byDegrees degrees: Double) {
        guard let item = selectedFurniture else { return }
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
        hasUnsavedChanges = true
        selectedItemID = placed.itemId
        isMovingSelectedFurniture = true
        sceneRevision += 1
        // 새 가구가 스캔 방의 벽 안/밖에 걸쳐 놓이면 방 안쪽으로 되밀어 넣는다.
        pendingWallResolveItemID = placed.itemId
    }

    /// 선택된 항목의 Y 회전을 절대 각도(도)로 설정합니다. 스톱 근처면 스냅합니다.
    /// 슬라이더 연속 조작이라 전체 리빌드 없이 노드만 갱신되도록 sceneRevision은 올리지 않습니다.
    func setSelectedRotation(degrees: Double) {
        guard let item = selectedFurniture,
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
        let snapped = Self.snapRotation(degrees)
        layout.furnitures[index].rotation.y = snapped * .pi / 180
        hasUnsavedChanges = true

        guard !isOffline, item.itemId > 0 else { return }
        Task {
            try? await editorService.updateTransform(itemID: item.itemId, transform: FurnitureTransform(
                position: item.position,
                rotation: layout.furnitures[index].rotation,
                scale: item.scale
            ))
        }
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
        layout.furnitures[index].position.y = floorY + clamped / 100
        hasUnsavedChanges = true

        guard !isOffline, item.itemId > 0 else { return }
        Task {
            try? await editorService.updateTransform(itemID: item.itemId, transform: FurnitureTransform(
                position: layout.furnitures[index].position,
                rotation: item.rotation,
                scale: item.scale
            ))
        }
    }

    /// 벽 색상 변경(4종 팝오버). 씬을 다시 지어 벽/배경에 반영합니다.
    func setWallColor(_ hex: String) {
        layout.space?.wallColor = hex
        hasUnsavedChanges = true
        sceneRevision += 1

        guard !isOffline, let spaceID = layout.space?.spaceId else { return }
        Task {
            try? await editorService.updateSpace(spaceID: spaceID, name: nil, area: nil, ceilingHeight: nil, wallColor: hex)
        }
    }

    var wallColorHex: String { layout.space?.wallColor ?? "#F2EDE5" }

    /// 뷰 모드를 직접 지정(Skyview/사람 뷰 토글).
    func setViewMode(_ mode: RoomViewMode) {
        guard viewMode != mode else { return }
        viewMode = mode
        if mode == .person {
            selectedItemID = nil
            isMovingSelectedFurniture = false
            isMeasuring = false
        }
        // 사람 뷰는 앱 전용 모드라 서버(3D/SKYVIEW만 지원)에 동기화하지 않는다.
        guard !isOffline, mode != .person else { return }
        Task {
            try? await editorService.updateViewMode(roomID: roomID, mode: mode)
        }
    }

    var isSkyview: Bool { viewMode == .skyView }
    var isPersonView: Bool { viewMode == .person }

    func replaceSelected(with furniture: FurnitureDetail) {
        guard let item = selectedFurniture,
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
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
        hasUnsavedChanges = true
        // 벽에 붙어 있던 가구가 더 큰 가구로 바뀌면 새 발자국이 벽을 뚫는다. 씬에 되밀기를 요청.
        pendingWallResolveItemID = item.itemId
        sceneRevision += 1

        guard !isOffline, item.itemId > 0 else { return }
        Task {
            try? await editorService.replaceFurniture(itemID: item.itemId, newFurnitureID: furniture.furnitureId)
        }
    }

    func deleteSelected() {
        guard let selectedItemID else { return }
        layout.furnitures.removeAll { $0.itemId == selectedItemID }
        hasUnsavedChanges = true
        let deletedID = selectedItemID
        self.selectedItemID = nil
        isMovingSelectedFurniture = false
        sceneRevision += 1

        guard !isOffline, deletedID > 0 else { return }
        Task {
            try? await editorService.deleteFurniture(itemID: deletedID)
        }
    }

    /// 선택된 문/창문을 벽으로 메웁니다(개구부 채우기). 프런트엔드 `deleteSelectedReference(true)` 대응.
    /// 문/창문을 제거하고 그 자리에 같은 크기·자세의 벽 색 패널을 세워 구멍을 막습니다.
    /// (`deleteSelected()`가 프런트엔드의 `deleteSelectedReference(false)` = 개구부로 남기기에 해당)
    func fillOpeningWithWall() {
        guard let item = selectedFurniture, Self.isReference(item),
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
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
        hasUnsavedChanges = true
        selectedItemID = nil
        isMovingSelectedFurniture = false
        sceneRevision += 1

        // 원래 문/창문이 서버 아이템이면 서버에서도 제거한다(벽 패널은 저장 metadata로 함께 나간다).
        guard !isOffline, item.itemId > 0 else { return }
        Task { try? await editorService.deleteFurniture(itemID: item.itemId) }
    }

    func toggleViewMode() {
        viewMode = viewMode == .threeD ? .skyView : .threeD
        guard !isOffline else { return }
        Task {
            try? await editorService.updateViewMode(roomID: roomID, mode: viewMode)
        }
    }

    /// 서버 metadata JSON 인코딩용. 로더는 `editedObjects`를 우선 읽으므로 나머지는 비워 둔다.
    private struct ExportedRoomMetadata: Encodable {
        var objects: [EditableScanItem] = []
        var doors: [EditableScanItem] = []
        var windows: [EditableScanItem] = []
        var openings: [EditableScanItem] = []
        var editedObjects: [EditableScanItem]
    }

    /// 서버에 저장된 룸인지(= 업로드 완료되어 projectID + 서버 roomID가 있는지).
    private var isServerRoom: Bool {
        guard projectID != nil else { return false }
        return !roomID.hasPrefix("local")
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }

        guard let projectID else {
            // 프로젝트 없이 연 룸(테스트 스캔 등)은 업로드할 곳이 없다.
            statusMessage = "프로젝트가 없어 서버에 저장할 수 없어요."
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
                roomID = created.id
                layout.roomId = created.id
                isOffline = false
                hasUnsavedChanges = false
                statusMessage = "스캔이 업로드되어 저장되었습니다."
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
            hasUnsavedChanges = false
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
            return item
        }

        let metadata = ExportedRoomMetadata(editedObjects: editedObjects)
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

    private func replaceLocalItemID(_ localID: Int, with serverID: Int) {
        guard let index = layout.furnitures.firstIndex(where: { $0.itemId == localID }) else { return }
        layout.furnitures[index].itemId = serverID
        if selectedItemID == localID { selectedItemID = serverID }
        sceneRevision += 1
    }
}
