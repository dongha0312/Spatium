import Foundation
import RoomPlan
import simd

struct EditableScanItem: Identifiable, Codable {
    var id: UUID
    var sourceType: String
    var detectedCategory: String
    var displayName: String
    var width: Double
    var height: Double
    var depth: Double
    var positionX: Double
    var positionY: Double
    var positionZ: Double
    /// 편집기에서 사용자가 돌린 Y축 회전(라디안). 스캔 원본은 0.
    var rotationY: Double = 0
    /// 스캔 당시 감지된 객체의 Y축 방향(라디안). RoomPlan transform에서 추출합니다.
    var detectedRotationY: Double = 0
    /// 사용자가 고른 3D 모델 파일명(확장자 제외). nil이면 카테고리 기본 모델을 사용합니다.
    var modelName: String? = nil
    /// 꾸미기 책장 위에 올려둔 피규어들(부모 로컬 transform 기준). 저장/복원용.
    var decorations: [PlacedDecoration]? = nil
    var isReplacementTarget: Bool
    var editNote: String

    var measurementSummary: String {
        "\(formatMeters(width)) x \(formatMeters(height)) x \(formatMeters(depth))m"
    }

    var iconName: String {
        switch sourceType {
        case "가구": "sofa"
        case "문": "door.left.hand.open"
        case "창문": "window.vertical.open"
        default: "square.dashed"
        }
    }

    static func makeItems(from room: CapturedRoom) -> [EditableScanItem] {
        var items = room.objects.enumerated().map { index, object in
            EditableScanItem(
                id: UUID(),
                sourceType: "가구",
                detectedCategory: String(describing: object.category),
                displayName: "\(String(describing: object.category)) \(index + 1)",
                dimensions: object.dimensions,
                transform: object.transform,
                isReplacementTarget: true,
                editNote: ""
            )
        }

        items += room.doors.enumerated().map { index, surface in
            EditableScanItem(surface: surface, sourceType: "문", index: index, isReplacementTarget: false)
        }
        items += room.windows.enumerated().map { index, surface in
            EditableScanItem(surface: surface, sourceType: "창문", index: index, isReplacementTarget: false)
        }
        items += room.openings.enumerated().map { index, surface in
            EditableScanItem(surface: surface, sourceType: "개구부", index: index, isReplacementTarget: false)
        }

        return items
    }

    /// 편집기에서 사용자가 직접 추가한 객체를 만들 때 사용합니다.
    init(userAddedNamed displayName: String, width: Double, height: Double, depth: Double) {
        self.id = UUID()
        self.sourceType = "가구"
        self.detectedCategory = "userAdded"
        self.displayName = displayName
        self.width = width
        self.height = height
        self.depth = depth
        self.positionX = 0
        self.positionY = height / 2
        self.positionZ = 0
        self.rotationY = 0
        self.isReplacementTarget = true
        self.editNote = "사용자 추가"
    }

    private init(
        id: UUID,
        sourceType: String,
        detectedCategory: String,
        displayName: String,
        dimensions: SIMD3<Float>,
        transform: simd_float4x4,
        isReplacementTarget: Bool,
        editNote: String
    ) {
        self.id = id
        self.sourceType = sourceType
        self.detectedCategory = detectedCategory
        self.displayName = displayName
        self.width = Double(dimensions.x)
        self.height = Double(dimensions.y)
        self.depth = Double(dimensions.z)
        self.positionX = Double(transform.columns.3.x)
        self.positionY = Double(transform.columns.3.y)
        self.positionZ = Double(transform.columns.3.z)
        // Y축 회전(라디안): 열 기준(column-major) Ry에서 θ = atan2(-m₀₂, m₀₀).
        self.detectedRotationY = Double(atan2(-transform.columns.0.z, transform.columns.0.x))
        self.isReplacementTarget = isReplacementTarget
        self.editNote = editNote
    }

    private init(surface: CapturedRoom.Surface, sourceType: String, index: Int, isReplacementTarget: Bool) {
        self.init(
            id: UUID(),
            sourceType: sourceType,
            detectedCategory: sourceType,
            displayName: "\(sourceType) \(index + 1)",
            dimensions: surface.dimensions,
            transform: surface.transform,
            isReplacementTarget: isReplacementTarget,
            editNote: ""
        )
    }

    private func formatMeters(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

extension EditableScanItem {
    /// 원시 RoomPlan export(objects/doors/windows)에서 편집 아이템을 만듭니다.
    /// (외부/테스트 JSON을 CapturedRoom 없이 직접 불러올 때 사용)
    static func makeItems(
        objects: [(category: String, dimensions: SIMD3<Float>, transform: simd_float4x4)],
        doors: [(dimensions: SIMD3<Float>, transform: simd_float4x4)] = [],
        windows: [(dimensions: SIMD3<Float>, transform: simd_float4x4)] = []
    ) -> [EditableScanItem] {
        var items = objects.enumerated().map { index, object in
            EditableScanItem(
                id: UUID(), sourceType: "가구", detectedCategory: object.category,
                displayName: "\(object.category) \(index + 1)",
                dimensions: object.dimensions, transform: object.transform,
                isReplacementTarget: true, editNote: ""
            )
        }
        items += doors.enumerated().map { index, door in
            EditableScanItem(
                id: UUID(), sourceType: "문", detectedCategory: "문", displayName: "문 \(index + 1)",
                dimensions: door.dimensions, transform: door.transform,
                isReplacementTarget: false, editNote: ""
            )
        }
        items += windows.enumerated().map { index, window in
            EditableScanItem(
                id: UUID(), sourceType: "창문", detectedCategory: "창문", displayName: "창문 \(index + 1)",
                dimensions: window.dimensions, transform: window.transform,
                isReplacementTarget: false, editNote: ""
            )
        }
        return items
    }
}
