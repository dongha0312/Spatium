import Foundation

/// A project grouping multiple scanned rooms. `id` is the server's `projectId`
/// once synced; locally-created (not-yet-synced) projects use a negative
/// placeholder id until the server call succeeds.
struct SpatiumProject: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var createdAt = Date()
    var rooms: [RoomRecord] = []
    /// 서버 목록이 내려준 방 개수(방 상세를 아직 안 불러왔을 때 표시에 사용).
    var roomCount: Int = 0

    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "이름 없는 프로젝트" : trimmed
    }

    /// 방 상세를 불러왔으면 실제 개수, 아니면 서버 목록의 roomCount.
    var displayRoomCount: Int {
        max(rooms.count, roomCount)
    }

    /// 서버에 저장된(동기화된) 프로젝트인지.
    var isSynced: Bool { !id.hasPrefix("local-") }

    var lastUpdatedAt: Date {
        rooms.map(\.uploadedAt).max() ?? createdAt
    }
}
