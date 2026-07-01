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
