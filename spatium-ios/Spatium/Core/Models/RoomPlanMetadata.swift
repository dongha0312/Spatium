import Foundation
import RoomPlan
import simd

struct RoomPlanMetadata: Codable {
    var roomType: String?
    var objects: [RoomPlanObjectMetadata]
    var doors: [RoomPlanSurfaceMetadata]
    var windows: [RoomPlanSurfaceMetadata]
    var openings: [RoomPlanSurfaceMetadata]

    init(room: CapturedRoom, roomType: String) {
        let trimmedRoomType = roomType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.roomType = trimmedRoomType.isEmpty ? nil : trimmedRoomType
        self.objects = room.objects.map { RoomPlanObjectMetadata(object: $0) }
        self.doors = room.doors.map { RoomPlanSurfaceMetadata(surface: $0) }
        self.windows = room.windows.map { RoomPlanSurfaceMetadata(surface: $0) }
        self.openings = room.openings.map { RoomPlanSurfaceMetadata(surface: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case roomType
        case objects
        case doors
        case windows
        case openings
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(roomType, forKey: .roomType)
        try container.encode(objects, forKey: .objects)
        try container.encode(doors, forKey: .doors)
        try container.encode(windows, forKey: .windows)
        try container.encode(openings, forKey: .openings)
    }
}

struct RoomPlanObjectMetadata: Codable {
    var category: String
    var dimensions: RoomPlanVector3
    var transform: RoomPlanMatrix4x4

    init(object: CapturedRoom.Object) {
        self.category = String(describing: object.category)
        self.dimensions = RoomPlanVector3(object.dimensions)
        self.transform = RoomPlanMatrix4x4(object.transform)
    }
}

struct RoomPlanSurfaceMetadata: Codable {
    var dimensions: RoomPlanVector3
    var transform: RoomPlanMatrix4x4

    init(surface: CapturedRoom.Surface) {
        self.dimensions = RoomPlanVector3(surface.dimensions)
        self.transform = RoomPlanMatrix4x4(surface.transform)
    }
}

struct RoomPlanVector3: Codable {
    var x: Float
    var y: Float
    var z: Float

    init(_ vector: SIMD3<Float>) {
        self.x = vector.x
        self.y = vector.y
        self.z = vector.z
    }
}

struct RoomPlanMatrix4x4: Codable {
    var columns: [[Float]]

    init(_ matrix: simd_float4x4) {
        self.columns = [
            [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w],
            [matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w],
            [matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w],
            [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w]
        ]
    }
}
