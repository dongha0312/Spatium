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

    /// 메시 export와 사진 JPEG 인코딩은 수 초짜리 동기 작업이라 백그라운드에서 실행한다.
    /// (메인 액터에서 그대로 돌리면 내보내기/업로드 동안 UI가 통째로 멈춘다)
    func exportPackage() async throws -> [URL] {
        // 메타데이터 JSON(변환행렬/치수 목록)은 가벼우므로 메인에서 인코딩하고,
        // 파일 쓰기 전부를 백그라운드로 넘긴다.
        let metadataData = try JSONEncoder.prettyPrinted.encode(
            RoomPlanMetadata(room: room, roomType: roomType, editedObjects: items)
        )
        let folderName = "Spatium-\(Self.fileStamp.string(from: createdAt))"
        let room = self.room
        let photos = self.photos
        return try await Task.detached {
            try Self.writePackageFiles(
                room: room,
                photos: photos,
                folderName: folderName,
                metadataData: metadataData
            )
        }.value
    }

    nonisolated private static func writePackageFiles(
        room: CapturedRoom,
        photos: [UIImage],
        folderName: String,
        metadataData: Data
    ) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(folderName, isDirectory: true)

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
        try metadataData.write(to: requestURL)

        return urls
    }

    /// 3D 편집 화면에서 방 메시를 렌더링하기 위한 USDZ만 내보냅니다. (메시 export는 백그라운드)
    func exportUSDZForEditing() async throws -> URL {
        let room = self.room
        return try await Task.detached {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("Spatium-Edit", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let url = folder.appendingPathComponent("room-scan-edit.usdz")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try room.export(to: url, metadataURL: nil, modelProvider: nil, exportOptions: .mesh)
            return url
        }.value
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
