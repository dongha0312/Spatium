import Foundation
import UIKit

// MARK: - 책장 꾸미기 / 피규어 편집

extension RoomEditorViewModel {
    static func isDecoratable(_ furniture: PlacedFurniture) -> Bool {
        furniture.modelName?.hasPrefix("editable_") == true
    }

    var selectedIsDecoratable: Bool {
        guard let item = selectedFurniture else { return false }
        return Self.isDecoratable(item)
    }

    var isDecorating: Bool { decoratingItemID != nil }

    var decoratingFurniture: PlacedFurniture? {
        guard let decoratingItemID else { return nil }
        return layout.furnitures.first { $0.itemId == decoratingItemID }
    }

    func beginDecorating() {
        guard let item = selectedFurniture, Self.isDecoratable(item) else { return }
        guard viewMode == .threeD else {
            statusMessage = "스카이뷰를 끈 뒤 책장 꾸미기를 시작해 주세요"
            return
        }
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
        let finishedItemID = decoratingItemID
        decoratingItemID = nil
        decorShelfLevels = []
        pendingFigure = nil
        selectedDecorID = nil
        statusMessage = nil
        // 프런트엔드는 꾸미기 완료 후 대상 책장을 다시 선택한다. 앱도 같은 흐름으로
        // 복귀해야 사용자가 곧바로 책장을 이동·교체하거나 다시 꾸밀 수 있다.
        if let finishedItemID,
           layout.furnitures.contains(where: { $0.itemId == finishedItemID }) {
            selectedItemID = finishedItemID
        }
    }

    static func figureDimensions(for item: FurnitureCatalogItem) -> (width: Double, height: Double, depth: Double) {
        let width = max(item.width, 0.02)
        let height = max(item.height, 0.02)
        let depth = max(item.depth, 0.02)
        let maxSide = max(width, height, depth)
        guard maxSide > figureMaxDimension else { return (width, height, depth) }
        let scale = figureMaxDimension / maxSide
        return (width * scale, height * scale, depth * scale)
    }

    static func isDecorFigure(_ item: FurnitureCatalogItem) -> Bool {
        item.category.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("figure") == .orderedSame
    }

    /// 프런트엔드 3dEditor의 꾸미기 카탈로그 규칙과 동일하게, 기본 카탈로그는
    /// figure 카테고리만 허용하고 사용자가 만든 모델은 저장 카테고리와 무관하게 허용한다.
    /// 큰 사용자 모델은 `figureDimensions(for:)`에서 최대 35cm로 비율 축소된다.
    static func isDecorCatalogItem(_ item: FurnitureCatalogItem) -> Bool {
        item.source == .user || isDecorFigure(item)
    }

    func prepareDecorPlacement(_ item: FurnitureCatalogItem) {
        guard isDecorating else { return }
        guard Self.isDecorCatalogItem(item) else {
            pendingFigure = nil
            statusMessage = "꾸미기 책장에는 사용자 소품이나 피규어만 올릴 수 있어요"
            return
        }
        selectedDecorID = nil
        pendingFigure = item
        statusMessage = "피규어를 놓을 선반의 윗면을 탭하세요"
    }

    func placePendingFigure(atLocal position: FurnitureTransform.Vector3) {
        guard let decoratingItemID, let pendingFigure,
              let index = layout.furnitures.firstIndex(where: { $0.itemId == decoratingItemID }) else { return }
        guard Self.isDecorCatalogItem(pendingFigure) else {
            self.pendingFigure = nil
            statusMessage = "꾸미기 책장에는 사용자 소품이나 피규어만 올릴 수 있어요"
            return
        }
        guard Self.isFiniteDecorPosition(position) else { return }
        recordHistoryStep()
        let dims = Self.figureDimensions(for: pendingFigure)
        let decoration = PlacedDecoration(
            decorId: nextDecorID,
            name: pendingFigure.name,
            modelName: pendingFigure.modelFileName,
            width: dims.width,
            height: dims.height,
            depth: dims.depth,
            position: position,
            rotationY: 0,
            scale: 1,
            catalogId: pendingFigure.id,
            category: pendingFigure.category,
            modelPath: pendingFigure.modelPath
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

    func placePendingFigure(on shelf: DecorShelfLevel) {
        guard decorShelfLevels.contains(where: { $0.id == shelf.id }) else { return }
        placePendingFigure(atLocal: .init(x: 0, y: shelf.height, z: 0))
    }

    func moveSelectedDecor(toLocal position: FurnitureTransform.Vector3) {
        guard let indices = selectedDecorIndices() else { return }
        guard let decoration = layout.furnitures[indices.furniture].decorations?[indices.decor] else { return }
        guard Self.isFiniteDecorPosition(position), decoration.position != position else { return }
        recordHistoryStep()
        layout.furnitures[indices.furniture].decorations?[indices.decor].position = position
        markLayoutChanged()
        statusMessage = nil
        sceneRevision += 1
    }

    func nudgeSelectedDecor(deltaX: Double, deltaZ: Double) {
        guard deltaX.isFinite, deltaZ.isFinite,
              let indices = selectedDecorIndices(),
              let decoration = layout.furnitures[indices.furniture].decorations?[indices.decor] else { return }
        let safePosition = clampedDecorPosition(
            .init(
                x: decoration.position.x + deltaX,
                y: decoration.position.y,
                z: decoration.position.z + deltaZ
            ),
            itemWidth: decoration.width,
            itemDepth: decoration.depth,
            scale: decoration.scale,
            furniture: layout.furnitures[indices.furniture]
        )
        moveSelectedDecor(toLocal: safePosition)
    }

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

    static func fallbackDecorShelfLevels(for furniture: PlacedFurniture) -> [DecorShelfLevel] {
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

    func replaceSelectedDecor(with item: FurnitureCatalogItem) {
        guard let indices = selectedDecorIndices(),
              let current = layout.furnitures[indices.furniture].decorations?[indices.decor] else { return }
        guard Self.isDecorCatalogItem(item) else {
            statusMessage = "꾸미기 책장에는 사용자 소품이나 피규어만 올릴 수 있어요"
            return
        }
        recordHistoryStep()
        let dimensions = Self.figureDimensions(for: item)
        layout.furnitures[indices.furniture].decorations?[indices.decor] = PlacedDecoration(
            decorId: current.decorId,
            name: item.name,
            modelName: item.modelFileName,
            width: dimensions.width,
            height: dimensions.height,
            depth: dimensions.depth,
            // 프런트엔드 replaceSelectedFigure와 같이 기존 바닥 지지점은 그대로 유지한다.
            // 새 모델이 더 커도 위치를 다시 중앙 쪽으로 당기지 않아 교체 전후가 튀지 않는다.
            position: current.position,
            rotationY: current.rotationY,
            scale: 1,
            catalogId: item.id,
            category: item.category,
            modelPath: item.modelPath
        )
        markLayoutChanged()
        statusMessage = nil
        sceneRevision += 1
        Haptics.impact(.light)
    }

    var selectedDecoration: PlacedDecoration? {
        guard let indices = selectedDecorIndices() else { return nil }
        return layout.furnitures[indices.furniture].decorations?[indices.decor]
    }

    var selectedDecorRotationDegrees: Double {
        guard let decoration = selectedDecoration else { return 0 }
        return (decoration.rotationY * 180 / .pi).rounded()
    }

    func setSelectedDecorRotation(degrees: Double) {
        guard let indices = selectedDecorIndices() else { return }
        let snapped = Self.snapRotation(degrees)
        guard layout.furnitures[indices.furniture].decorations?[indices.decor].rotationY != snapped * .pi / 180 else { return }
        recordHistoryStep()
        layout.furnitures[indices.furniture].decorations?[indices.decor].rotationY = snapped * .pi / 180
        markLayoutChanged()
    }

    var selectedDecorSizeCm: Double {
        guard let decoration = selectedDecoration else { return 0 }
        let maxSide = max(decoration.width, decoration.height, decoration.depth)
        return (maxSide * decoration.scale * 100).rounded()
    }

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

    private func clampedDecorPosition(
        _ position: FurnitureTransform.Vector3,
        itemWidth: Double,
        itemDepth: Double,
        scale: Double,
        furniture: PlacedFurniture
    ) -> FurnitureTransform.Vector3 {
        let footprintRadius = max(itemWidth, itemDepth) * max(scale, 0.001) / 2
        let maxX = max((furniture.width ?? 0.8) / 2 - footprintRadius - 0.015, 0)
        let maxZ = max((furniture.depth ?? 0.3) / 2 - footprintRadius - 0.015, 0)
        return .init(
            x: min(max(position.x, -maxX), maxX),
            y: position.y,
            z: min(max(position.z, -maxZ), maxZ)
        )
    }

    private func selectedDecorIndices() -> (furniture: Int, decor: Int)? {
        guard let decoratingItemID, let selectedDecorID,
              let furnitureIndex = layout.furnitures.firstIndex(where: { $0.itemId == decoratingItemID }),
              let decorIndex = layout.furnitures[furnitureIndex].decorations?
                  .firstIndex(where: { $0.decorId == selectedDecorID }) else { return nil }
        return (furnitureIndex, decorIndex)
    }

    private static func isFiniteDecorPosition(_ position: FurnitureTransform.Vector3) -> Bool {
        position.x.isFinite && position.y.isFinite && position.z.isFinite
    }

    private func horizontalPositionDescription(_ x: Double) -> String {
        let value = centimeters(abs(x))
        if value < 1 { return "가로 중앙" }
        return x < 0 ? "왼쪽 \(value)센티미터" : "오른쪽 \(value)센티미터"
    }

    private func depthPositionDescription(_ z: Double) -> String {
        let value = centimeters(abs(z))
        if value < 1 { return "앞뒤 중앙" }
        return z > 0 ? "앞쪽 \(value)센티미터" : "뒤쪽 \(value)센티미터"
    }

    private func centimeters(_ meters: Double) -> Int {
        Int((meters * 100).rounded())
    }
}
