import Combine
import Foundation

struct UserFurnitureMetricDimensions: Equatable, Sendable {
    let width: Double
    let height: Double
    let depth: Double

    /// 현재 계약은 m단위지만 예전 저장분에는 cm/mm 숫자가 그대로 남아 있을 수 있다.
    /// 일반 가구의 최대 축이 10m를 넘으면 단위가 다른 레거시 데이터로 판단한다.
    nonisolated static func meters(width: Double, height: Double, depth: Double) -> Self {
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

struct UserFurniture: Codable, Identifiable, Equatable, Sendable {
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
            modelPath: serverModelPath,
            source: .user
        )
    }
}

/// GLB 복사와 카탈로그 JSON 인코딩처럼 동기식인 파일 작업을 전용 직렬 큐에서 처리한다.
/// 같은 저장소의 작업 순서를 보존해 모델 파일과 catalog.json의 트랜잭션 경계도 유지한다.
private nonisolated final class UserFurnitureDiskStore: @unchecked Sendable {
    private struct ModelReplacement {
        let destination: URL
        let backup: URL?
    }

    private let storageDirectory: URL
    private let metadataURL: URL
    private let queue = DispatchQueue(
        label: "com.spatium.user-furniture-disk-store",
        qos: .utility
    )
    private let initialLoadOperationObserver: (@Sendable (Bool) -> Void)?

    init(
        storageDirectory: URL,
        metadataURL: URL,
        initialLoadOperationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.storageDirectory = storageDirectory
        self.metadataURL = metadataURL
        self.initialLoadOperationObserver = initialLoadOperationObserver
    }

    func load() async -> [UserFurniture] {
        await performWithoutThrowing { [self] in
            initialLoadOperationObserver?(Thread.isMainThread)
            guard let data = try? Data(contentsOf: metadataURL) else { return [] }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let decoded = try? decoder.decode([UserFurniture].self, from: data) else {
                return []
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
            let sorted = migrated.sorted { $0.createdAt > $1.createdAt }

            // 레거시 단위를 고친 스냅샷은 같은 직렬 큐에서 바로 기록해,
            // 초기 로드 직후 들어오는 변경보다 늦게 디스크를 덮어쓰지 않게 한다.
            if migrated != decoded {
                try? writeCatalog(sorted)
            }
            return sorted
        }
    }

    func add(
        sourceModelURL: URL?,
        modelFileName: String,
        catalog: [UserFurniture]
    ) async throws {
        try await perform { [self] in
            try createStorageDirectory()
            let replacement: ModelReplacement?
            if let sourceModelURL {
                replacement = try replaceModel(
                    at: sourceModelURL,
                    modelFileName: modelFileName
                )
            } else {
                replacement = nil
            }
            do {
                try writeCatalog(catalog)
                commit(replacement)
            } catch {
                rollback(replacement)
                throw error
            }
        }
    }

    func promote(
        sourceModelURL: URL,
        modelFileName: String,
        catalog: [UserFurniture]
    ) async throws {
        try await perform { [self] in
            try createStorageDirectory()
            let destination = modelURL(for: modelFileName)
            let usesNewFileName = sourceModelURL.standardizedFileURL
                != destination.standardizedFileURL
            let replacement = usesNewFileName
                ? try replaceModel(at: sourceModelURL, modelFileName: modelFileName)
                : nil
            do {
                try writeCatalog(catalog)
                commit(replacement)
                if usesNewFileName {
                    try? FileManager.default.removeItem(at: sourceModelURL)
                }
            } catch {
                rollback(replacement)
                throw error
            }
        }
    }

    func remove(modelFileName: String, catalog: [UserFurniture]) async throws {
        try await perform { [self] in
            try createStorageDirectory()
            try writeCatalog(catalog)
            let modelURL = modelURL(for: modelFileName)
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try? FileManager.default.removeItem(at: modelURL)
            }
        }
    }

    func persist(_ catalog: [UserFurniture]) async throws {
        try await perform { [self] in
            try createStorageDirectory()
            try writeCatalog(catalog)
        }
    }

    func containsModel(fileName: String) async -> Bool {
        await performWithoutThrowing { [self] in
            FileManager.default.fileExists(atPath: modelURL(for: fileName).path)
        }
    }

    func installDownloadedModel(at temporaryURL: URL, fileName: String) async throws {
        try await perform { [self] in
            try createStorageDirectory()
            let destination = modelURL(for: fileName)
            guard !FileManager.default.fileExists(atPath: destination.path) else { return }

            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
            } catch {
                try FileManager.default.copyItem(at: temporaryURL, to: destination)
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }
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

    private func createStorageDirectory() throws {
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
    }

    private func writeCatalog(_ catalog: [UserFurniture]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func replaceModel(at sourceURL: URL, modelFileName: String) throws -> ModelReplacement? {
        let destination = modelURL(for: modelFileName)
        guard sourceURL.standardizedFileURL != destination.standardizedFileURL else { return nil }

        let stagingURL = storageDirectory
            .appendingPathComponent(".model-staging-\(UUID().uuidString)")
            .appendingPathExtension("glb")
        let backupURL = storageDirectory
            .appendingPathComponent(".model-backup-\(UUID().uuidString)")
            .appendingPathExtension("glb")
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            try? FileManager.default.removeItem(at: stagingURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
            let hadExistingDestination = FileManager.default.fileExists(atPath: destination.path)
            if hadExistingDestination {
                try FileManager.default.moveItem(at: destination, to: backupURL)
            }
            do {
                try FileManager.default.moveItem(at: stagingURL, to: destination)
            } catch {
                if hadExistingDestination {
                    try? FileManager.default.moveItem(at: backupURL, to: destination)
                }
                throw error
            }
            return ModelReplacement(
                destination: destination,
                backup: hadExistingDestination ? backupURL : nil
            )
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
    }

    private func commit(_ replacement: ModelReplacement?) {
        guard let backup = replacement?.backup else { return }
        try? FileManager.default.removeItem(at: backup)
    }

    private func rollback(_ replacement: ModelReplacement?) {
        guard let replacement else { return }
        try? FileManager.default.removeItem(at: replacement.destination)
        if let backup = replacement.backup {
            try? FileManager.default.moveItem(at: backup, to: replacement.destination)
        }
    }

    private func modelURL(for fileName: String) -> URL {
        storageDirectory.appendingPathComponent(fileName).appendingPathExtension("glb")
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
    private let diskStore: UserFurnitureDiskStore
    private let accessTokenProvider: (() -> String?)?
    private var isRefreshingFromBackend = false
    private var isMutationInProgress = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    private var initialLoadTask: Task<Void, Never>?

    init(
        storageDirectory: URL? = nil,
        accessTokenProvider: (() -> String?)? = nil,
        initialLoadOperationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        let storageDirectory = storageDirectory ?? Self.defaultStorageDirectory
        let metadataURL = storageDirectory.appendingPathComponent("catalog.json")
        self.storageDirectory = storageDirectory
        diskStore = UserFurnitureDiskStore(
            storageDirectory: storageDirectory,
            metadataURL: metadataURL,
            initialLoadOperationObserver: initialLoadOperationObserver
        )
        self.accessTokenProvider = accessTokenProvider
        initialLoadTask = Task { [weak self] in
            await self?.loadInitialCatalog()
        }
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
            return try await add(
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
            return try await add(
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
        return try await add(
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

        for remote in remoteUsers {
            if !(await diskStore.containsModel(fileName: remote.id)),
               let modelPath = remote.modelUrl,
               let temporaryURL = try? await FurnitureService().downloadModel(path: modelPath) {
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                try? await diskStore.installDownloadedModel(at: temporaryURL, fileName: remote.id)
            }
        }

        try? await withMutationLock {
            let localOnlyItems = items.filter { $0.serverModelPath == nil }
            let synchronized = remoteUsers.map { remote in
                let existing = items.first { $0.id == remote.id }
                let dimensions = UserFurnitureMetricDimensions.meters(
                    width: remote.dimensions.x,
                    height: remote.dimensions.y,
                    depth: remote.dimensions.z
                )
                return UserFurniture(
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
            }
            let refreshedItems = (localOnlyItems + synchronized).sorted {
                $0.createdAt > $1.createdAt
            }
            try await diskStore.persist(refreshedItems)
            items = refreshedItems
        }
    }

    /// 404 폴백으로 기기에만 남은 가구를 백엔드와 동기화한다.
    /// 하나의 실패가 서버 미배포나 네트워크 문제일 수 있으므로 이번 새로고침의 나머지 업로드도 중단한다.
    @discardableResult
    func synchronizePendingFurniture(using uploader: FurnitureUploader) async -> Int {
        await waitForInitialCatalogLoad()
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
                try await promotePendingFurniture(
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
                    ?? item.id,
                modelPath: item.modelUrl
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
    ) async throws {
        try await withMutationLock {
            guard !response.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let index = items.firstIndex(where: {
                      $0.id == furniture.id && $0.serverModelPath == nil
                  }) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            var synchronizedItems = items
            synchronizedItems[index] = UserFurniture(
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
            try await diskStore.promote(
                sourceModelURL: sourceURL,
                modelFileName: response.id,
                catalog: synchronizedItems
            )
            items = synchronizedItems
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
    ) async throws -> UserFurniture {
        try await withMutationLock {
            let id = id ?? "usr_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
            let modelFileName = id
            let dimensions = UserFurnitureMetricDimensions.meters(
                width: width,
                height: height,
                depth: depth
            )
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
            let updatedItems = [furniture] + items
            try await diskStore.add(
                sourceModelURL: sourceModelURL,
                modelFileName: modelFileName,
                catalog: updatedItems
            )
            items = updatedItems
            return furniture
        }
    }

    func remove(_ furniture: UserFurniture) async throws {
        try await withMutationLock {
            let updatedItems = items.filter { $0.id != furniture.id }
            try await diskStore.remove(
                modelFileName: furniture.modelFileName,
                catalog: updatedItems
            )
            items = updatedItems
        }
    }

    func delete(_ furniture: UserFurniture) async throws {
        let token = AuthTokenStore.shared.accessToken
        if furniture.serverModelPath != nil,
           token != nil,
           token?.hasPrefix("mock_") == false {
            try await FurnitureService().deleteUserFurniture(id: furniture.id)
        }
        try await remove(furniture)
    }

    nonisolated static func modelURL(for fileName: String) -> URL? {
        modelURL(for: fileName, storageDirectory: defaultStorageDirectory)
    }

    func waitForInitialCatalogLoad() async {
        if let initialLoadTask {
            await initialLoadTask.value
        }
    }

    private func loadInitialCatalog() async {
        let loadedItems = await diskStore.load()
        items = loadedItems
        initialLoadTask = nil
    }

    private func withMutationLock<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        await acquireMutationLock()
        do {
            await waitForInitialCatalogLoad()
            try Task.checkCancellation()
            let result = try await operation()
            releaseMutationLock()
            return result
        } catch {
            releaseMutationLock()
            throw error
        }
    }

    private func acquireMutationLock() async {
        guard isMutationInProgress else {
            isMutationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    private func releaseMutationLock() {
        guard !mutationWaiters.isEmpty else {
            isMutationInProgress = false
            return
        }
        mutationWaiters.removeFirst().resume()
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
