import Foundation

struct RoomScanPackage {
    var items: [EditableScanItem]
    var usdzURL: URL?
    var floorColor: String?
}

struct RoomScanAssetService {
    enum LoadError: LocalizedError {
        case noFiles
        case invalidURL(String)
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .noFiles:
                return "이 방에 연결된 스캔 파일이 없습니다."
            case let .invalidURL(value):
                return "스캔 파일 주소를 열 수 없습니다: \(value)"
            case .invalidJSON:
                return "스캔 JSON을 해석할 수 없습니다."
            }
        }
    }

    func loadPackage(for room: RoomRecord) async throws -> RoomScanPackage? {
        guard room.hasScanRenderFiles else { return nil }

        let jsonURLString = room.renderJSONReference
        let usdzURLString = room.renderUSDZReference

        let jsonURL: URL?
        if let jsonURLString {
            jsonURL = try await resolveURL(jsonURLString)
        } else {
            jsonURL = nil
        }

        let usdzURL: URL?
        if let usdzURLString {
            usdzURL = try await resolveURL(usdzURLString)
        } else {
            usdzURL = nil
        }

        guard jsonURL != nil || usdzURL != nil else {
            throw LoadError.noFiles
        }

        let cacheDirectory = try cacheDirectory(for: room.id)
        let localJSONURL: URL?
        if let jsonURL {
            localJSONURL = try await downloadIfNeeded(jsonURL, into: cacheDirectory, preferredFileName: "room-\(room.id).json")
        } else {
            localJSONURL = nil
        }

        let localUSDZURL: URL?
        if let usdzURL {
            localUSDZURL = try await downloadIfNeeded(usdzURL, into: cacheDirectory, preferredFileName: "room-\(room.id).usdz")
        } else {
            localUSDZURL = nil
        }

        let items: [EditableScanItem]
        let floorColor: String?
        if let localJSONURL {
            let data = try Data(contentsOf: localJSONURL)
            guard let export = try? JSONDecoder().decode(RoomPlanExportJSON.self, from: data) else {
                throw LoadError.invalidJSON
            }
            items = export.items()
            floorColor = export.floorColor
        } else {
            items = []
            floorColor = nil
        }

        return RoomScanPackage(items: items, usdzURL: localUSDZURL, floorColor: floorColor)
    }

    /// 방 목록 표시용 항목 개수. 스캔 JSON만 내려받아 파싱합니다. (무거운 USDZ는 받지 않음)
    /// 실패하면 nil을 돌려 기존 표시값을 유지하게 합니다.
    func loadItemCount(for room: RoomRecord) async -> Int? {
        guard let jsonReference = room.renderJSONReference,
              let jsonURL = try? await resolveURL(jsonReference),
              let directory = try? cacheDirectory(for: room.id),
              let localURL = try? await downloadIfNeeded(jsonURL, into: directory, preferredFileName: "room-\(room.id).json"),
              let data = try? Data(contentsOf: localURL),
              let export = try? JSONDecoder().decode(RoomPlanExportJSON.self, from: data) else {
            return nil
        }
        return export.items().count
    }

    /// 에디터 저장 등으로 서버 메타데이터가 바뀐 뒤 호출해, 다음 로드가 새 파일을 받게 합니다.
    func invalidateCache(forRoomID roomID: String) {
        guard let directory = try? cacheDirectory(for: roomID) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func resolveURL(_ value: String) async throws -> URL {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }

        let baseURL = await MainActor.run { SpatiumAPIEnvironment.shared.baseURL }
        guard let baseURL else { throw LoadError.invalidURL(value) }

        if value.hasPrefix("/") {
            guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
                throw LoadError.invalidURL(value)
            }
            return url
        }

        return baseURL.appendingPathComponent(value)
    }

    private func cacheDirectory(for roomID: String) throws -> URL {
        let safeID = roomID.replacingOccurrences(of: "/", with: "_")
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomScans", isDirectory: true)
            .appendingPathComponent(safeID, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func downloadIfNeeded(_ sourceURL: URL, into directory: URL, preferredFileName: String) async throws -> URL {
        if sourceURL.isFileURL {
            return sourceURL
        }

        let destination = directory.appendingPathComponent(preferredFileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 20
        // 서버 메타데이터의 절대 URL이 외부 호스트를 가리켜도 토큰이 새어 나가지 않도록,
        // 우리 API 서버와 같은 호스트일 때만 인증 헤더를 붙인다.
        let apiHost = await MainActor.run { SpatiumAPIEnvironment.shared.baseURL?.host }
        if let apiHost, sourceURL.host == apiHost,
           let token = await MainActor.run(body: { AuthTokenStore.shared.accessToken }) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw SpatiumAPIError.server(
                statusCode: httpResponse.statusCode,
                code: nil,
                message: "스캔 파일을 내려받지 못했습니다. (HTTP \(httpResponse.statusCode))"
            )
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }
}
