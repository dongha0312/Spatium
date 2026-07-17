import Combine
import Foundation

struct UserFurnitureMetricDimensions: Equatable {
    let width: Double
    let height: Double
    let depth: Double

    /// 현재 계약은 m단위지만 예전 저장분에는 cm/mm 숫자가 그대로 남아 있을 수 있다.
    /// 일반 가구의 최대 축이 10m를 넘으면 단위가 다른 레거시 데이터로 판단한다.
    static func meters(width: Double, height: Double, depth: Double) -> Self {
        let source = [width, height, depth].map { value in
            value.isFinite && value > 0 ? value : 0.04
        }
        let maximum = source.max() ?? 0.04
        let divisor: Double
        if maximum > 500 {
            divisor = 1_000 // mm → m
        } else if maximum > 10 {
            divisor = 100 // cm → m
        } else {
            divisor = 1
        }
        return .init(
            width: max(source[0] / divisor, 0.04),
            height: max(source[1] / divisor, 0.04),
            depth: max(source[2] / divisor, 0.04)
        )
    }
}

struct UserFurniture: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var normalizedName: String
    var category: String
    var categoryLabel: String
    var width: Double
    var height: Double
    var depth: Double
    var modelFileName: String
    var serverModelPath: String?
    var createdAt: Date

    var catalogItem: FurnitureCatalogItem {
        let dimensions = UserFurnitureMetricDimensions.meters(
            width: width,
            height: height,
            depth: depth
        )
        let catalogGroup = switch category {
        case "table": "책상"
        case "storage": "수납"
        default: categoryLabel
        }
        return FurnitureCatalogItem(
            id: id,
            name: name,
            group: catalogGroup,
            category: category,
            width: dimensions.width,
            height: dimensions.height,
            depth: dimensions.depth,
            modelFileName: modelFileName,
            source: .user
        )
    }
}

@MainActor
final class UserFurnitureStore: ObservableObject {
    typealias FurnitureUploader = (
        _ glbFileURL: URL,
        _ fileName: String,
        _ metadata: FurnitureCreateMetadata
    ) async throws -> FurnitureCreateResponse

    @Published private(set) var items: [UserFurniture] = []
    @Published private(set) var builtInItems: [FurnitureCatalogItem] = FurnitureCatalog.items

    private let storageDirectory: URL
    private let metadataURL: URL
    private let accessTokenProvider: (() -> String?)?
    private var isRefreshingFromBackend = false

    init(
        storageDirectory: URL? = nil,
        accessTokenProvider: (() -> String?)? = nil
    ) {
        self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory
        metadataURL = self.storageDirectory.appendingPathComponent("catalog.json")
        self.accessTokenProvider = accessTokenProvider
        load()
    }

    var catalogItems: [FurnitureCatalogItem] {
        builtInItems + items.map(\.catalogItem)
    }

    func save(
        name: String,
        normalizedName: String,
        category: String,
        categoryLabel: String,
        width: Double,
        height: Double,
        depth: Double,
        sourceModelURL: URL?
    ) async throws -> UserFurniture {
        guard let sourceModelURL,
              let token = AuthTokenStore.shared.accessToken,
              !token.hasPrefix("mock_") else {
            return try add(
                name: name,
                normalizedName: normalizedName,
                category: category,
                categoryLabel: categoryLabel,
                width: width,
                height: height,
                depth: depth,
                sourceModelURL: sourceModelURL
            )
        }

        let accessed = sourceModelURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceModelURL.stopAccessingSecurityScopedResource() } }
        let dimensions = UserFurnitureMetricDimensions.meters(
            width: width,
            height: height,
            depth: depth
        )
        let metadata = FurnitureCreateMetadata(
            nameKr: name.trimmingCharacters(in: .whitespacesAndNewlines),
            name: normalizedName.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            categoryKr: categoryLabel,
            dimensions: .init(
                x: dimensions.width,
                y: dimensions.height,
                z: dimensions.depth
            )
        )
        let response: FurnitureCreateResponse
        do {
            response = try await FurnitureService().createUserFurniture(
                modelFileURL: sourceModelURL,
                fileName: sourceModelURL.lastPathComponent.isEmpty ? "furniture.glb" : sourceModelURL.lastPathComponent,
                metadata: metadata
            )
        } catch let error as SpatiumAPIError where Self.shouldSaveLocally(after: error) {
            // 배포된 Spring 서버에 사용자 가구 생성 엔드포인트가 아직 없더라도,
            // 보정한 GLB를 잃지 않고 이 기기의 내 가구/에디터 카탈로그에서 사용한다.
            // 이 항목은 다음 카탈로그 새로고침 때 동일한 서버 계약으로 재시도된다.
            return try add(
                name: name,
                normalizedName: normalizedName,
                category: category,
                categoryLabel: categoryLabel,
                width: width,
                height: height,
                depth: depth,
                sourceModelURL: sourceModelURL
            )
        }
        return try add(
            id: response.id,
            name: name,
            normalizedName: normalizedName,
            category: category,
            categoryLabel: categoryLabel,
            width: dimensions.width,
            height: dimensions.height,
            depth: dimensions.depth,
            sourceModelURL: sourceModelURL,
            serverModelPath: response.modelUrl
        )
    }

    /// 서버의 공통 NoResourceFound 응답. 인증/검증/서버 내부 오류까지 로컬 성공으로
    /// 위장하지 않고, 아직 배포되지 않은 생성 경로인 경우에만 기기 저장으로 폴백한다.
    static func shouldSaveLocally(after error: SpatiumAPIError) -> Bool {
        guard case let .server(statusCode, code, _) = error else { return false }
        return statusCode == 404 && (code == nil || code == "NOT_FOUND")
    }

    func refreshFromBackend() async {
        let accessToken = if let accessTokenProvider {
            accessTokenProvider()
        } else {
            AuthTokenStore.shared.accessToken
        }
        guard let token = accessToken,
              !token.hasPrefix("mock_") else {
            // 로그아웃은 인증 세션만 종료하는 동작이다. 이 기기에 저장한 GLB와
            // 서버 가구 캐시까지 삭제하면 재로그인 후 목록 복구가 서버 상태에
            // 의존하게 되므로, 무인증 새로고침에서는 기존 카탈로그를 그대로 보존한다.
            return
        }
        guard !isRefreshingFromBackend else { return }
        isRefreshingFromBackend = true
        defer { isRefreshingFromBackend = false }

        if let catalog = try? await FurnitureService().fetchCatalog() {
            updateBuiltInCatalog(catalog)
        }

        // 이전에 서버가 404를 반환해 기기에만 저장했던 GLB를 먼저 업로드한다.
        // 업로드가 성공하면 서버가 발급한 id/modelUrl로 로컬 항목을 교체한다.
        _ = await synchronizePendingFurniture { fileURL, fileName, metadata in
            try await FurnitureService().createUserFurniture(
                modelFileURL: fileURL,
                fileName: fileName,
                metadata: metadata
            )
        }

        guard let remoteUsers = try? await FurnitureService().fetchUserCatalog() else { return }

        let localOnlyItems = items.filter { $0.serverModelPath == nil }
        var synchronized: [UserFurniture] = []
        for remote in remoteUsers {
            let existing = items.first { $0.id == remote.id }
            let dimensions = UserFurnitureMetricDimensions.meters(
                width: remote.dimensions.x,
                height: remote.dimensions.y,
                depth: remote.dimensions.z
            )
            let furniture = UserFurniture(
                id: remote.id,
                name: remote.name,
                normalizedName: existing?.normalizedName ?? remote.name,
                category: remote.category,
                categoryLabel: remote.group,
                width: dimensions.width,
                height: dimensions.height,
                depth: dimensions.depth,
                modelFileName: remote.id,
                serverModelPath: remote.modelUrl,
                createdAt: existing?.createdAt ?? .distantPast
            )
            if Self.modelURL(for: remote.id, storageDirectory: storageDirectory) == nil,
               let modelPath = remote.modelUrl,
               let temporaryURL = try? await FurnitureService().downloadModel(path: modelPath) {
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
                try? FileManager.default.moveItem(
                    at: temporaryURL,
                    to: storageDirectory.appendingPathComponent(remote.id).appendingPathExtension("glb")
                )
            }
            synchronized.append(furniture)
        }
        items = (localOnlyItems + synchronized).sorted { $0.createdAt > $1.createdAt }
        try? persist()
    }

    /// 404 폴백으로 기기에만 남은 가구를 백엔드와 동기화한다.
    /// 하나의 실패가 서버 미배포나 네트워크 문제일 수 있으므로 이번 새로고침의 나머지 업로드도 중단한다.
    @discardableResult
    func synchronizePendingFurniture(using uploader: FurnitureUploader) async -> Int {
        let pendingIDs = items
            .filter { $0.serverModelPath == nil }
            .map(\.id)
        var synchronizedCount = 0

        for pendingID in pendingIDs {
            guard let furniture = items.first(where: { $0.id == pendingID }),
                  furniture.serverModelPath == nil,
                  let sourceURL = Self.modelURL(
                      for: furniture.modelFileName,
                      storageDirectory: storageDirectory
                  ) else {
                continue
            }

            do {
                let response = try await uploader(
                    sourceURL,
                    sourceURL.lastPathComponent,
                    Self.createMetadata(for: furniture)
                )
                try promotePendingFurniture(
                    furniture,
                    response: response,
                    sourceURL: sourceURL
                )
                synchronizedCount += 1
            } catch is CancellationError {
                break
            } catch {
                break
            }
        }

        return synchronizedCount
    }

    private func updateBuiltInCatalog(_ catalog: [FurnitureCatalogResponseItem]) {
        let defaults = catalog.map { item in
            let bundled = FurnitureCatalog.items.first { $0.id == item.id }
            return FurnitureCatalogItem(
                id: item.id,
                name: item.name,
                group: item.group,
                category: item.category,
                width: item.dimensions.x,
                height: item.dimensions.y,
                depth: item.dimensions.z,
                modelFileName: bundled?.modelFileName
                    ?? URL(string: item.modelUrl ?? "")?.deletingPathExtension().lastPathComponent
                    ?? item.id
            )
        }
        if !defaults.isEmpty {
            // 서버가 중복 ID를 내려줘도 크래시하지 않도록 첫 항목 유지로 병합한다.
            let remoteByID = Dictionary(defaults.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let knownIDs = Set(FurnitureCatalog.items.map(\.id))
            builtInItems = FurnitureCatalog.items.map { remoteByID[$0.id] ?? $0 }
                + defaults.filter { !knownIDs.contains($0.id) }
        }
    }

    private static func createMetadata(for furniture: UserFurniture) -> FurnitureCreateMetadata {
        FurnitureCreateMetadata(
            nameKr: furniture.name,
            name: furniture.normalizedName,
            category: furniture.category,
            categoryKr: furniture.categoryLabel,
            dimensions: .init(
                x: furniture.width,
                y: furniture.height,
                z: furniture.depth
            )
        )
    }

    private func promotePendingFurniture(
        _ furniture: UserFurniture,
        response: FurnitureCreateResponse,
        sourceURL: URL
    ) throws {
        guard !response.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = items.firstIndex(where: {
                  $0.id == furniture.id && $0.serverModelPath == nil
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let destination = storageDirectory
            .appendingPathComponent(response.id)
            .appendingPathExtension("glb")
        let usesNewFileName = sourceURL.standardizedFileURL != destination.standardizedFileURL

        if usesNewFileName {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }

        let previous = items[index]
        items[index] = UserFurniture(
            id: response.id,
            name: furniture.name,
            normalizedName: furniture.normalizedName,
            category: furniture.category,
            categoryLabel: furniture.categoryLabel,
            width: furniture.width,
            height: furniture.height,
            depth: furniture.depth,
            modelFileName: response.id,
            serverModelPath: response.modelUrl,
            createdAt: furniture.createdAt
        )

        do {
            try persist()
            if usesNewFileName {
                try? FileManager.default.removeItem(at: sourceURL)
            }
        } catch {
            items[index] = previous
            if usesNewFileName {
                try? FileManager.default.removeItem(at: destination)
            }
            throw error
        }
    }

    @discardableResult
    func add(
        id: String? = nil,
        name: String,
        normalizedName: String,
        category: String,
        categoryLabel: String,
        width: Double,
        height: Double,
        depth: Double,
        sourceModelURL: URL?,
        serverModelPath: String? = nil
    ) throws -> UserFurniture {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        let id = id ?? "usr_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let modelFileName = id
        let destination = storageDirectory.appendingPathComponent(modelFileName).appendingPathExtension("glb")
        let dimensions = UserFurnitureMetricDimensions.meters(
            width: width,
            height: height,
            depth: depth
        )

        if let sourceModelURL {
            let accessed = sourceModelURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { sourceModelURL.stopAccessingSecurityScopedResource() }
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceModelURL, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }

        let furniture = UserFurniture(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedName: normalizedName.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            categoryLabel: categoryLabel,
            width: dimensions.width,
            height: dimensions.height,
            depth: dimensions.depth,
            modelFileName: modelFileName,
            serverModelPath: serverModelPath,
            createdAt: Date()
        )
        items.insert(furniture, at: 0)
        do {
            try persist()
        } catch {
            items.removeAll { $0.id == furniture.id }
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return furniture
    }

    func remove(_ furniture: UserFurniture) throws {
        let previous = items
        items.removeAll { $0.id == furniture.id }
        do {
            try persist()
            if let modelURL = Self.modelURL(for: furniture.modelFileName, storageDirectory: storageDirectory) {
                try? FileManager.default.removeItem(at: modelURL)
            }
        } catch {
            items = previous
            throw error
        }
    }

    func delete(_ furniture: UserFurniture) async throws {
        let token = AuthTokenStore.shared.accessToken
        if furniture.serverModelPath != nil,
           token != nil,
           token?.hasPrefix("mock_") == false {
            try await FurnitureService().deleteUserFurniture(id: furniture.id)
        }
        try remove(furniture)
    }

    nonisolated static func modelURL(for fileName: String) -> URL? {
        modelURL(for: fileName, storageDirectory: defaultStorageDirectory)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder.spatiumAPI.decode([UserFurniture].self, from: data) else {
            items = []
            return
        }
        let migrated = decoded.map { furniture in
            let dimensions = UserFurnitureMetricDimensions.meters(
                width: furniture.width,
                height: furniture.height,
                depth: furniture.depth
            )
            var result = furniture
            result.width = dimensions.width
            result.height = dimensions.height
            result.depth = dimensions.depth
            return result
        }
        items = migrated.sorted { $0.createdAt > $1.createdAt }
        if migrated != decoded {
            try? persist()
        }
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.spatiumAPI.encode(items)
        try data.write(to: metadataURL, options: .atomic)
    }

    private nonisolated static var defaultStorageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Spatium/UserFurniture", isDirectory: true)
    }

    private nonisolated static func modelURL(for fileName: String, storageDirectory: URL) -> URL? {
        let url = storageDirectory.appendingPathComponent(fileName).appendingPathExtension("glb")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
