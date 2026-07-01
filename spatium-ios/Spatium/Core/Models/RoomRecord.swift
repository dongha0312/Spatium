import Foundation

struct RoomRecord: Identifiable {
    let id = UUID()
    let roomType: String
    let itemCount: Int
    let photoCount: Int
    let uploadedAt: Date
    let fileName: String
}
