import Foundation

// MARK: - 가구 추가 / 이동 / 크기 / 교체 / 제거

extension RoomEditorViewModel {
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

    /// 카탈로그 상품을 방에 배치합니다. 선택한 정확한 GLB 파일명을 함께 실어 렌더합니다.
    /// 여러 개 추가 시 원점에 겹치지 않도록 작은 격자로 흩어 놓습니다.
    func place(catalogItem: FurnitureCatalogItem) {
        guard viewMode != .person else {
            statusMessage = "1인칭 시점에서는 가구를 추가할 수 없어요"
            return
        }
        recordHistoryStep()
        let n = layout.furnitures.count
        let col = Double(n % 3) - 1
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
        pendingWallResolveItemID = placed.itemId
    }

    /// 선택된 항목의 Y 회전을 절대 각도(도)로 설정합니다. 스톱 근처면 스냅합니다.
    func setSelectedRotation(degrees: Double) {
        guard let item = selectedFurniture, !Self.isWallInfill(item),
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
        let snapped = Self.snapRotation(degrees)
        guard layout.furnitures[index].rotation.y != snapped * .pi / 180 else { return }
        recordHistoryStep()
        layout.furnitures[index].rotation.y = snapped * .pi / 180
        markLayoutChanged()
    }

    var selectedRotationDegrees: Double {
        guard let item = selectedFurniture else { return 0 }
        return (item.rotation.y * 180 / .pi).rounded()
    }

    static func snapRotation(_ value: Double) -> Double {
        let nearest = rotationStops.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
        return abs(nearest - value) <= 4 ? nearest : value
    }

    static func isWallInfill(_ furniture: PlacedFurniture) -> Bool {
        furniture.modelName == wallInfillModelName
    }

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

    var selectedIsReference: Bool {
        guard let item = selectedFurniture else { return false }
        return Self.isReference(item)
    }

    var selectedIsWallInfill: Bool {
        guard let item = selectedFurniture else { return false }
        return Self.isWallInfill(item)
    }

    /// 씬이 방 메시에서 찾아낸 실제 바닥 높이(월드 Y)를 적용합니다.
    func adoptFloorY(_ y: Double) {
        floorY = y
    }

    var selectedElevationCm: Double {
        guard let item = selectedFurniture else { return 0 }
        return ((item.position.y - floorY) * 100).rounded()
    }

    var selectedMaxElevationCm: Double {
        guard selectedSupportsElevation, let item = selectedFurniture else { return 0 }
        let ceiling = layout.space?.ceilingHeight ?? 2.4
        let height = item.height ?? 0.5
        return max(0, ((ceiling - height) * 100).rounded())
    }

    var selectedSupportsElevation: Bool {
        guard let item = selectedFurniture else { return false }
        return !Self.isReference(item) && !Self.isWallInfill(item)
    }

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

    var selectedSupportsResize: Bool { selectedSupportsElevation }

    var selectedSizeCm: Double {
        guard let item = selectedFurniture else { return 0 }
        let maxSide = max(item.width ?? 0.5, item.depth ?? 0.5, item.height ?? 0.5)
        return (maxSide * 100).rounded()
    }

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

    func finishSelectedSizeAdjust() {
        guard let selectedItemID else { return }
        pendingWallResolveItemID = selectedItemID
    }

    func replaceSelected(with furniture: FurnitureDetail) {
        guard let item = selectedFurniture, !Self.isWallInfill(item),
              let index = layout.furnitures.firstIndex(where: { $0.itemId == item.itemId }) else { return }
        recordHistoryStep()
        layout.furnitures[index].furnitureId = furniture.furnitureId
        layout.furnitures[index].furnitureName = furniture.name
        layout.furnitures[index].width = furniture.width
        layout.furnitures[index].depth = furniture.depth
        layout.furnitures[index].height = furniture.height
        layout.furnitures[index].modelName = furniture.modelName
            ?? FurnitureCatalog.defaultModelName(matching: furniture.name)
            ?? layout.furnitures[index].modelName
        layout.furnitures[index].decorations = nil
        markLayoutChanged()
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

    private func takeLocalItemID() -> Int {
        defer { nextLocalItemID -= 1 }
        return nextLocalItemID
    }
}
