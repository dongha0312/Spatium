import Foundation

/// 프런트엔드 `roomMetadata.js`가 저장하는 치수·행렬 형식. 앱 전용
/// `EditableScanItem` 형식과 함께 읽고 써서 같은 방을 웹/앱에서 왕복할 수 있게 한다.
nonisolated struct FrontendRoomDimensions: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

nonisolated struct FrontendRoomTransform: Codable, Equatable, Sendable {
    struct Components: Equatable, Sendable {
        let position: FurnitureTransform.Vector3
        let rotationY: Double
        let scale: FurnitureTransform.Vector3
    }

    let columns: [[Double]]

    init(
        position: FurnitureTransform.Vector3,
        rotationY: Double,
        scale: FurnitureTransform.Vector3
    ) {
        let cosine = cos(rotationY)
        let sine = sin(rotationY)
        columns = [
            [cosine * scale.x, 0, -sine * scale.x, 0],
            [0, scale.y, 0, 0],
            [sine * scale.z, 0, cosine * scale.z, 0],
            [position.x, position.y, position.z, 1]
        ]
    }

    var components: Components {
        func value(_ column: Int, _ row: Int, fallback: Double = 0) -> Double {
            guard columns.indices.contains(column), columns[column].indices.contains(row) else {
                return fallback
            }
            let result = columns[column][row]
            return result.isFinite ? result : fallback
        }

        let columnX = (value(0, 0), value(0, 1), value(0, 2))
        let columnY = (value(1, 0), value(1, 1), value(1, 2))
        let columnZ = (value(2, 0), value(2, 1), value(2, 2))
        let scaleX = max(hypot(columnX.0, hypot(columnX.1, columnX.2)), 0.000_001)
        let scaleY = max(hypot(columnY.0, hypot(columnY.1, columnY.2)), 0.000_001)
        let scaleZ = max(hypot(columnZ.0, hypot(columnZ.1, columnZ.2)), 0.000_001)
        let rotationY = atan2(-columnX.2 / scaleX, columnX.0 / scaleX)

        return Components(
            position: .init(x: value(3, 0), y: value(3, 1), z: value(3, 2)),
            rotationY: rotationY.isFinite ? rotationY : 0,
            scale: .init(x: scaleX, y: scaleY, z: scaleZ)
        )
    }
}

nonisolated struct FrontendRoomDecoration: Codable, Equatable, Sendable {
    let catalogId: String?
    let name: String
    let category: String?
    let path: String?
    let modelUrl: String?
    let dimensions: FrontendRoomDimensions
    let transform: FrontendRoomTransform

    init(
        decoration: PlacedDecoration,
        parentHeight: Double,
        parentScale: FurnitureTransform.Vector3
    ) {
        catalogId = decoration.catalogId
        name = decoration.name
        category = decoration.category ?? "figure"
        path = decoration.modelPath
        modelUrl = decoration.modelPath
        dimensions = .init(
            x: decoration.width,
            y: decoration.height,
            z: decoration.depth
        )

        let scaleX = max(parentScale.x, 0.000_001)
        let scaleY = max(parentScale.y, 0.000_001)
        let scaleZ = max(parentScale.z, 0.000_001)
        let actualParentHeight = parentHeight * scaleY
        transform = FrontendRoomTransform(
            position: .init(
                x: decoration.position.x / scaleX,
                y: (decoration.position.y - actualParentHeight / 2) / scaleY,
                z: decoration.position.z / scaleZ
            ),
            rotationY: decoration.rotationY,
            // 웹에서는 소품이 책장 root의 자식이므로 부모 scale이 다시 곱해진다.
            // 앱에서 보던 실제 크기를 유지하도록 그만큼 역보정해 저장한다.
            scale: .init(
                x: decoration.scale / scaleX,
                y: decoration.scale / scaleY,
                z: decoration.scale / scaleZ
            )
        )
    }

    func placedDecoration(
        index: Int,
        parentHeight: Double,
        parentScale: FurnitureTransform.Vector3
    ) -> PlacedDecoration {
        let components = transform.components
        let actualParentHeight = parentHeight * parentScale.y
        let inheritedScale = (
            components.scale.x * parentScale.x
                + components.scale.y * parentScale.y
                + components.scale.z * parentScale.z
        ) / 3
        return PlacedDecoration(
            decorId: index + 1,
            name: name,
            modelName: Self.resolveModelName(
                catalogId: catalogId,
                path: modelUrl ?? path
            ),
            width: dimensions.x,
            height: dimensions.y,
            depth: dimensions.z,
            position: .init(
                x: components.position.x * parentScale.x,
                y: actualParentHeight / 2 + components.position.y * parentScale.y,
                z: components.position.z * parentScale.z
            ),
            rotationY: components.rotationY,
            scale: max(inheritedScale, 0.001),
            catalogId: catalogId,
            category: category,
            modelPath: modelUrl ?? path
        )
    }

    private static func resolveModelName(catalogId: String?, path: String?) -> String? {
        if let catalogId,
           let catalog = FurnitureCatalog.items.first(where: { $0.id == catalogId }) {
            return catalog.modelFileName
        }
        if let catalogId, catalogId.hasPrefix("usr_") {
            return catalogId
        }
        guard let path else { return nil }
        let pathWithoutQuery = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        let parts = pathWithoutQuery.split(separator: "/")
        if parts.last == "model", parts.count >= 2 {
            return String(parts[parts.count - 2])
        }
        guard let last = parts.last else { return nil }
        return String(last).replacingOccurrences(
            of: #"\.[Gg][Ll][Bb]$"#,
            with: "",
            options: .regularExpression
        )
    }
}

nonisolated struct FrontendRoomObject: Codable, Equatable, Sendable {
    let catalogId: String?
    let name: String?
    let category: String?
    let path: String?
    let modelUrl: String?
    let dimensions: FrontendRoomDimensions
    let transform: FrontendRoomTransform
    let decorations: [FrontendRoomDecoration]?

    init(furniture: PlacedFurniture) {
        let catalog = FurnitureCatalog.items.first { $0.modelFileName == furniture.modelName }
        let modelPath = Self.frontendModelPath(for: furniture.modelName)
        catalogId = catalog?.id
        name = furniture.furnitureName
        category = catalog?.category ?? furniture.furnitureName
        path = modelPath
        modelUrl = modelPath
        let width = furniture.width ?? 0.5
        let height = furniture.height ?? 0.5
        let depth = furniture.depth ?? 0.5
        dimensions = .init(x: width, y: height, z: depth)
        transform = FrontendRoomTransform(
            position: .init(
                x: furniture.position.x,
                y: furniture.position.y + height * furniture.scale.y / 2,
                z: furniture.position.z
            ),
            rotationY: furniture.rotation.y,
            scale: furniture.scale
        )
        decorations = furniture.decorations?.map {
            FrontendRoomDecoration(
                decoration: $0,
                parentHeight: height,
                parentScale: furniture.scale
            )
        }
    }

    func editableScanItem(sourceType: String, index: Int) -> EditableScanItem {
        let components = transform.components
        let width = dimensions.x * components.scale.x
        let height = dimensions.y * components.scale.y
        let depth = dimensions.z * components.scale.z
        let displayName = name ?? category ?? sourceType
        var item = EditableScanItem(
            userAddedNamed: displayName,
            width: width,
            height: height,
            depth: depth
        )
        item.sourceType = sourceType
        item.detectedCategory = category ?? sourceType
        item.displayName = name ?? "\(sourceType) \(index + 1)"
        item.positionX = components.position.x
        item.positionY = components.position.y
        item.positionZ = components.position.z
        item.detectedRotationY = components.rotationY
        item.rotationY = 0
        item.modelName = FrontendRoomDecoration.resolveObjectModelName(
            catalogId: catalogId,
            path: modelUrl ?? path,
            category: category
        )
        item.decorations = decorations?.enumerated().map { offset, decoration in
            decoration.placedDecoration(
                index: offset,
                parentHeight: dimensions.y,
                parentScale: components.scale
            )
        }
        item.isReplacementTarget = sourceType == "가구"
        item.editNote = "웹 편집 복원"
        return item
    }

    private static func frontendModelPath(for modelName: String?) -> String? {
        guard let modelName else { return nil }
        if modelName.hasPrefix("editable_") {
            return "/data/3d_models/editable_furniture/\(modelName).glb"
        }
        return nil
    }
}

private nonisolated extension FrontendRoomDecoration {
    static func resolveObjectModelName(
        catalogId: String?,
        path: String?,
        category: String?
    ) -> String? {
        resolveModelName(catalogId: catalogId, path: path)
            ?? FurnitureCatalog.defaultModelName(matching: category ?? "")
    }
}
