import Foundation
import RoomPlan
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

        let package = RoomPlanMetadata(room: room, roomType: roomType)
        let data = try JSONEncoder.prettyPrinted.encode(package)
        try data.write(to: requestURL)

        return urls
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
