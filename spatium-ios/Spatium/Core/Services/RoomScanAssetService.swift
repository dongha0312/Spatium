import Foundation

nonisolated struct RoomScanPackage: Sendable {
    var items: [EditableScanItem]
    var usdzURL: URL?
    var wallColor: String?
    var floorColor: String?
}

private nonisolated struct RoomScanDecodedMetadata: Sendable {
    var items: [EditableScanItem]
    var wallColor: String?
    var floorColor: String?
}

/// 로컬 방 스캔 캐시의 파일 작업과 JSON 변환을 앱 전체 공용 utility 큐에서 직렬화한다.
/// 방 목록의 병렬 항목 수 조회와 편집기 진입이 겹쳐도 같은 캐시 파일을 동시에 교체하지 않는다.
private nonisolated final class RoomScanAssetDiskStore: @unchecked Sendable {
    static let shared = RoomScanAssetDiskStore(rootDirectoryURL: defaultRootDirectoryURL())

    private let rootDirectoryURL: URL
    private let operationObserver: (@Sendable (Bool) -> Void)?
    private let queue = DispatchQueue(
        label: "com.spatium.room-scan-asset-disk-store",
        qos: .utility
    )

    init(
        rootDirectoryURL: URL,
        operationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.operationObserver = operationObserver
    }

    func cacheDirectory(for roomID: String) async throws -> URL {
        try await perform { [self] in
            operationObserver?(Thread.isMainThread)
            let directoryURL = roomDirectory(for: roomID)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            return directoryURL
        }
    }

    func cachedFileURL(in directoryURL: URL, preferredFileName: String) async -> URL? {
        await performWithoutThrowing { [self] in
            operationObserver?(Thread.isMainThread)
            let fileURL = directoryURL.appendingPathComponent(preferredFileName)
            return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
        }
    }

    func installDownloadedFile(
        at temporaryURL: URL,
        in directoryURL: URL,
        preferredFileName: String
    ) async throws -> URL {
        try await perform { [self] in
            operationObserver?(Thread.isMainThread)
            let destinationURL = directoryURL.appendingPathComponent(preferredFileName)

            // 같은 방의 병렬 요청이 먼저 설치를 끝냈다면 중복 교체 없이 해당 캐시를 재사용한다.
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: temporaryURL)
                return destinationURL
            }

            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
                return destinationURL
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }
        }
    }

    func decodeMetadata(at fileURL: URL) async throws -> RoomScanDecodedMetadata? {
        try await perform { [self] in
            operationObserver?(Thread.isMainThread)
            let data = try Data(contentsOf: fileURL)
            guard let export = try? JSONDecoder().decode(RoomPlanExportJSON.self, from: data) else {
                return nil
            }
            return RoomScanDecodedMetadata(
                items: export.items(),
                wallColor: export.wallColor,
                floorColor: export.floorColor
            )
        }
    }

    func invalidateCache(for roomID: String) async {
        await performWithoutThrowing { [self] in
            operationObserver?(Thread.isMainThread)
            try? FileManager.default.removeItem(at: roomDirectory(for: roomID))
        }
    }

    private func roomDirectory(for roomID: String) -> URL {
        let safeID = roomID.replacingOccurrences(of: "/", with: "_")
        return rootDirectoryURL.appendingPathComponent(safeID, isDirectory: true)
    }

    private static func defaultRootDirectoryURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomScans", isDirectory: true)
    }

    private func perform<T>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performWithoutThrowing<T>(
        _ operation: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: operation())
            }
        }
    }
}

nonisolated struct RoomScanAssetService: Sendable {
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

    private let diskStore: RoomScanAssetDiskStore

    init() {
        self.diskStore = .shared
    }

    init(
        cacheRootURL: URL,
        diskOperationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.diskStore = RoomScanAssetDiskStore(
            rootDirectoryURL: cacheRootURL,
            operationObserver: diskOperationObserver
        )
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

        let cacheDirectory = try await diskStore.cacheDirectory(for: room.id)
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
        let wallColor: String?
        let floorColor: String?
        if let localJSONURL {
            guard let metadata = try await diskStore.decodeMetadata(at: localJSONURL) else {
                throw LoadError.invalidJSON
            }
            items = metadata.items
            wallColor = metadata.wallColor
            floorColor = metadata.floorColor
        } else {
            items = []
            wallColor = nil
            floorColor = nil
        }

        return RoomScanPackage(items: items, usdzURL: localUSDZURL, wallColor: wallColor, floorColor: floorColor)
    }

    /// 방 목록 표시용 항목 개수. 스캔 JSON만 내려받아 파싱합니다. (무거운 USDZ는 받지 않음)
    /// 실패하면 nil을 돌려 기존 표시값을 유지하게 합니다.
    func loadItemCount(for room: RoomRecord) async -> Int? {
        guard let jsonReference = room.renderJSONReference,
              let jsonURL = try? await resolveURL(jsonReference),
              let directory = try? await diskStore.cacheDirectory(for: room.id),
              let localURL = try? await downloadIfNeeded(jsonURL, into: directory, preferredFileName: "room-\(room.id).json"),
              let metadata = try? await diskStore.decodeMetadata(at: localURL) else {
            return nil
        }
        return metadata.items.count
    }

    /// 에디터 저장 등으로 서버 메타데이터가 바뀐 뒤 호출해, 다음 로드가 새 파일을 받게 합니다.
    func invalidateCache(forRoomID roomID: String) async {
        await diskStore.invalidateCache(for: roomID)
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

    private func downloadIfNeeded(_ sourceURL: URL, into directory: URL, preferredFileName: String) async throws -> URL {
        if sourceURL.isFileURL {
            return sourceURL
        }

        if let cachedURL = await diskStore.cachedFileURL(
            in: directory,
            preferredFileName: preferredFileName
        ) {
            return cachedURL
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

        return try await diskStore.installDownloadedFile(
            at: temporaryURL,
            in: directory,
            preferredFileName: preferredFileName
        )
    }
}
