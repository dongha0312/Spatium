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

    func placePendingFigure(on shelf: DecorShelfLevel) {
        guard decorShelfLevels.contains(where: { $0.id == shelf.id }) else { return }
        placePendingFigure(atLocal: .init(x: 0, y: shelf.height, z: 0))
    }

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
