import Foundation
import RoomPlan
import simd
import UIKit

struct ScanProject {
    var room: CapturedRoom
    var photos: [UIImage] = []
    var createdAt = Date()
    var roomType = ""
    var items: [EditableScanItem]

    var resolvedRoomType: String {
        let trimmed = roomType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "이름 없는 공간" : trimmed
    }

    init(room: CapturedRoom, photos: [UIImage] = []) {
        self.room = room
        self.photos = photos
        self.items = EditableScanItem.makeItems(from: room)
    }

    func exportPackage() throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Spatium-\(Self.fileStamp.string(from: createdAt))", isDirectory: true)

        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let roomURL = folder.appendingPathComponent("room-scan.usdz")
        let requestURL = folder.appendingPathComponent("ai-edit-request.json")
        var urls = [roomURL, requestURL]

        try room.export(to: roomURL, metadataURL: nil, modelProvider: nil, exportOptions: .mesh)

        for (index, photo) in photos.enumerated() {
            if let data = photo.jpegData(compressionQuality: 0.8) {
                let photoURL = folder.appendingPathComponent("room-photo-\(index + 1).jpg")
                try data.write(to: photoURL)
                urls.append(photoURL)
            }
        }

        // 편집기에서 수정/추가/삭제한 객체 목록(items)을 함께 실어 보냅니다.
        let package = RoomPlanMetadata(room: room, roomType: roomType, editedObjects: items)
        let data = try JSONEncoder.prettyPrinted.encode(package)
        try data.write(to: requestURL)

        return urls
    }

    /// 3D 편집 화면에서 방 메시를 렌더링하기 위한 USDZ만 내보냅니다.
    func exportUSDZForEditing() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Spatium-Edit", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appendingPathComponent("room-scan-edit.usdz")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try room.export(to: url, metadataURL: nil, modelProvider: nil, exportOptions: .mesh)
        return url
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// Rough footprint (meters) from the bounding box of wall center positions,
    /// used to register the room server-side before the user names it.
    var estimatedFootprint: (width: Double, depth: Double) {
        let positions = room.walls.map { SIMD2<Float>($0.transform.columns.3.x, $0.transform.columns.3.z) }
        guard !positions.isEmpty else { return (4, 4) }
        let xs = positions.map(\.x)
        let zs = positions.map(\.y)
        let width = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        let depth = Double((zs.max() ?? 0) - (zs.min() ?? 0))
        return (max(width, 1), max(depth, 1))
    }

    var estimatedCeilingHeight: Double {
        let heights = room.walls.map { Double($0.dimensions.y) }
        return heights.max() ?? 2.4
    }
}
