import Combine
import Foundation
import SwiftUI

enum ProjectCachePersistenceState: Equatable, Sendable {
    case idle
    case saved(Date)
    case failed(message: String)

    var failureMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}

/// 프로젝트 캐시의 인코딩·파일 I/O를 메인 스레드 밖에서 순서대로 처리한다.
/// revision이 더 큰 작업을 먼저 받았다면 뒤늦게 도착한 오래된 작업은 건너뛰어
/// 연속 편집이나 로그아웃 중 이전 스냅샷이 최신 상태를 덮어쓰지 않게 한다.
private nonisolated final class ProjectCacheDiskStore: @unchecked Sendable {
    enum MutationResult: Sendable {
        case applied(Date)
        case superseded
    }

    private let cacheFileURL: URL
    private let queue = DispatchQueue(
        label: "com.spatium.project-cache-disk-store",
        qos: .utility
    )
    private let operationObserver: (@Sendable (Bool) -> Void)?

    /// 전용 직렬 큐에서만 접근한다.
    private var highestAttemptedRevision: UInt64 = 0

    init(
        cacheFileURL: URL,
        operationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.cacheFileURL = cacheFileURL
        self.operationObserver = operationObserver
    }

    func load() async throws -> [SpatiumProject] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    operationObserver?(Thread.isMainThread)
                    guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
                        continuation.resume(returning: [])
                        return
                    }

                    let data = try Data(contentsOf: cacheFileURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let projects = try decoder.decode([SpatiumProject].self, from: data)
                    continuation.resume(returning: projects)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func save(_ projects: [SpatiumProject], revision: UInt64) async throws -> MutationResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard revision > highestAttemptedRevision else {
                        continuation.resume(returning: .superseded)
                        return
                    }
                    // 실패하더라도 이보다 오래된 작업이 나중에 디스크를 되돌리지 못하게 한다.
                    highestAttemptedRevision = revision
                    operationObserver?(Thread.isMainThread)

                    try FileManager.default.createDirectory(
                        at: cacheFileURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(projects)
                    try data.write(to: cacheFileURL, options: .atomic)
                    continuation.resume(returning: .applied(Date()))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func clear(revision: UInt64) async throws -> MutationResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard revision > highestAttemptedRevision else {
                        continuation.resume(returning: .superseded)
                        return
                    }
                    highestAttemptedRevision = revision
                    operationObserver?(Thread.isMainThread)

                    if FileManager.default.fileExists(atPath: cacheFileURL.path) {
                        try FileManager.default.removeItem(at: cacheFileURL)
                    }
                    continuation.resume(returning: .applied(Date()))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [SpatiumProject] = []
    @Published var lastErrorMessage: String?
    @Published private(set) var cachePersistenceState: ProjectCachePersistenceState = .idle

    private let service = ProjectService()
    private let cacheDiskStore: ProjectCacheDiskStore
    private let authenticationStateProvider: () -> Bool
    private let automaticallyRefresh: Bool
    private var cancellables: Set<AnyCancellable> = []
    private var isRefreshing = false
    private var cacheRevision: UInt64 = 0

    init(
        cacheFileURL: URL? = nil,
        authenticationStateProvider: (() -> Bool)? = nil,
        cacheOperationObserver: (@Sendable (Bool) -> Void)? = nil,
        automaticallyRefresh: Bool = true
    ) {
        let resolvedCacheFileURL = cacheFileURL ?? Self.defaultCacheFileURL()
        self.cacheDiskStore = ProjectCacheDiskStore(
            cacheFileURL: resolvedCacheFileURL,
            operationObserver: cacheOperationObserver
        )
        let resolvedAuthenticationStateProvider = authenticationStateProvider ?? {
            AuthTokenStore.shared.isLoggedIn
        }
        self.authenticationStateProvider = resolvedAuthenticationStateProvider
        self.automaticallyRefresh = automaticallyRefresh
        // 생성 시점의 인증 상태를 고정해, 게스트로 시작한 스토어가 로그인 전환 중
        // 게스트 캐시를 계정 프로젝트처럼 뒤늦게 불러오지 않게 한다.
        let shouldLoadInitialCache = resolvedAuthenticationStateProvider()

        // 로그아웃하면 이전 계정 데이터가 다음 사용자에게 남지 않도록 캐시를 비운다.
        AuthTokenStore.shared.$isLoggedIn
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] loggedIn in
                guard let self else { return }
                if loggedIn {
                    Task { await self.refresh(silently: true) }
                } else {
                    self.clearLocalData()
                }
            }
            .store(in: &cancellables)

        Task { [weak self] in
            await self?.loadInitialCacheAndRefresh(shouldLoadCache: shouldLoadInitialCache)
        }
    }

    /// 로그아웃/계정 전환 시 메모리와 디스크 캐시를 모두 비운다.
    private func clearLocalData() {
        projects = []
        lastErrorMessage = nil
        cachePersistenceState = .idle
        let revision = nextCacheRevision()
        let cacheDiskStore = cacheDiskStore

        Task { [weak self] in
            do {
                let result = try await cacheDiskStore.clear(revision: revision)
                guard let self, revision == cacheRevision else { return }
                if case .applied = result {
                    cachePersistenceState = .idle
                }
            } catch {
                guard let self, revision == cacheRevision else { return }
                recordCachePersistenceFailure(error)
            }
        }
    }

    private nonisolated static func defaultCacheFileURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("projects.json")
    }

    /// 게스트(비로그인)로 만들어져 아직 서버에 없는 로컬 프로젝트 수.
    /// 로그인하면 서버 목록이 캐시를 덮어써 이 프로젝트들이 사라지므로,
    /// 로그인 화면이 사전 경고를 띄우는 데 사용한다.
    nonisolated static func guestLocalProjectCount(
        cacheFileURL: URL? = nil,
        cacheOperationObserver: (@Sendable (Bool) -> Void)? = nil
    ) async -> Int {
        let diskStore = ProjectCacheDiskStore(
            cacheFileURL: cacheFileURL ?? defaultCacheFileURL(),
            operationObserver: cacheOperationObserver
        )
        let cached = (try? await diskStore.load()) ?? []
        return cached.filter { $0.id.hasPrefix("local-") }.count
    }

    private func loadInitialCacheAndRefresh(shouldLoadCache: Bool) async {
        if shouldLoadCache {
            let revisionBeforeLoad = cacheRevision
            let cachedProjects = (try? await cacheDiskStore.load()) ?? []
            guard !Task.isCancelled else { return }

            // 로드 중 로그아웃·로컬 편집·새 저장이 발생했다면 이전 파일 스냅샷을 적용하지 않는다.
            if authenticationStateProvider(), revisionBeforeLoad == cacheRevision {
                projects = cachedProjects
            }
        }

        guard automaticallyRefresh, !Task.isCancelled else { return }
        await refresh(silently: true)
    }

    /// 서버에서 최신 프로젝트 목록을 받아옵니다. 실패 시 기존(캐시/로컬)을 유지합니다.
    func refresh(silently: Bool = false) async {
        guard authenticationStateProvider(), !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // 서버 목록으로 통째로 교체하면 이미 불러온 방 목록과 업로드 전 로컬 방
            // (스캔 직후 placeholder)이 화면에서 사라진다. 같은 프로젝트는 기존 rooms를
            // 유지하고, 방 목록은 상세 진입 시 loadRooms가 최신으로 갱신한다.
            // uniqueKeysWithValues는 중복 키에서 크래시한다. 서버가 같은 ID를 두 번 내려줘도
            // (백엔드 버그) 앱이 죽지 않도록 첫 항목을 유지하는 병합을 쓴다.
            let existingByID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            projects = try await service.fetchProjects().map { remote in
                guard let existing = existingByID[remote.id] else { return remote }
                var merged = remote
                merged.rooms = existing.rooms
                merged.roomCount = max(remote.roomCount, existing.rooms.count)
                return merged
            }
            lastErrorMessage = nil
            await refreshRoomCounts(silently: silently)
            _ = await persistCurrentCache()
        } catch is CancellationError {
            return
        } catch {
            if !silently {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func createProject(name: String) async throws -> SpatiumProject {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.emptyProjectName
        }

        if !authenticationStateProvider() {
            let local = SpatiumProject(id: Self.newLocalID(), name: trimmed)
            projects.insert(local, at: 0)
            _ = await persistCurrentCache()
            return local
        }

        do {
            let created = try await service.createProject(name: trimmed)
            projects.insert(created, at: 0)
            lastErrorMessage = nil
            _ = await persistCurrentCache()
            return created
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    /// 스캔 직후 즉시 UI에 보여줄 **로컬** 룸을 만듭니다. (서버 룸은 업로드 시점에 생성)
    /// replacingLocalRoomID: 같은 세션에서 "다시 스캔"한 경우, 업로드 전인 이전 스캔의
    /// 로컬 placeholder를 넘기면 중복으로 쌓이지 않고 교체됩니다. (서버 룸은 유지)
    @discardableResult
    func registerLocalRoom(
        projectID: String,
        roomName: String,
        area: Double,
        replacingLocalRoomID: String? = nil
    ) -> RoomRecord {
        if let replacingLocalRoomID, replacingLocalRoomID.hasPrefix("local-"),
           let index = projects.firstIndex(where: { $0.id == projectID }) {
            projects[index].rooms.removeAll { $0.id == replacingLocalRoomID }
        }
        let local = RoomRecord(
            id: Self.newLocalID(),
            roomType: roomName,
            itemCount: 0,
            photoCount: 0,
            uploadedAt: Date(),
            fileName: "",
            area: area
        )
        insertRoom(local, projectID: projectID)
        return local
    }

    /// 스캔 파일(metadata JSON + usdz)로 서버에 룸을 생성하고, 로컬 룸을 서버 룸으로 교체합니다.
    @discardableResult
    func uploadRoom(
        projectID: String,
        replacingLocalRoomID localRoomID: String?,
        roomName: String,
        metadataURL: URL,
        usdzURL: URL,
        itemCount: Int,
        photoCount: Int
    ) async throws -> RoomRecord {
        var created = try await service.createRoom(
            projectID: projectID, roomName: roomName, metadataURL: metadataURL, usdzURL: usdzURL
        )
        created.itemCount = itemCount
        created.photoCount = photoCount
        lastErrorMessage = nil

        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return created }
        if let localRoomID, let roomIndex = projects[index].rooms.firstIndex(where: { $0.id == localRoomID }) {
            projects[index].rooms[roomIndex] = created
        } else {
            projects[index].rooms.insert(created, at: 0)
        }
        projects[index].roomCount = max(projects[index].roomCount, projects[index].rooms.count)
        _ = await persistCurrentCache()
        return created
    }

    /// 3D 에디터가 저장 과정에서 직접 생성한 서버 룸을 목록에 반영합니다.
    /// (uploadRoom과 같은 교체 규칙: 로컬 placeholder가 있으면 그 자리를 대체)
    func adoptUploadedRoom(_ room: RoomRecord, projectID: String, replacingLocalRoomID localRoomID: String?) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        if let localRoomID, let roomIndex = projects[index].rooms.firstIndex(where: { $0.id == localRoomID }) {
            projects[index].rooms[roomIndex] = room
        } else if !projects[index].rooms.contains(where: { $0.id == room.id }) {
            projects[index].rooms.insert(room, at: 0)
        }
        projects[index].roomCount = max(projects[index].roomCount, projects[index].rooms.count)
        scheduleCachePersistence()
    }

    func loadRooms(projectID: String, silently: Bool = false) async {
        guard !projectID.hasPrefix("local-") else { return }
        do {
            let rooms = try await service.fetchRooms(projectID: projectID)
            guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
            projects[index].rooms = rooms
            projects[index].roomCount = rooms.count
            lastErrorMessage = nil
            // 목록 API에는 항목 수가 없으므로, 각 방의 스캔 JSON에서 실제 개수를 받아 채운다.
            await refreshItemCounts(projectID: projectID, rooms: rooms)
            _ = await persistCurrentCache()
        } catch is CancellationError {
            return
        } catch {
            if !silently {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// 방별 스캔 JSON(가벼움)을 병렬로 받아 항목 개수를 갱신합니다. 도착하는 대로 행이 갱신됩니다.
    private func refreshItemCounts(projectID: String, rooms: [RoomRecord]) async {
        let assetService = RoomScanAssetService()
        await withTaskGroup(of: (String, Int?).self) { group in
            for room in rooms where room.hasScanRenderFiles {
                group.addTask {
                    (room.id, await assetService.loadItemCount(for: room))
                }
            }
            for await (roomID, count) in group {
                guard let count else { continue }
                updateRoom(roomID: roomID, projectID: projectID, shouldPersist: false) {
                    $0.itemCount = count
                }
            }
        }
    }

    func renameProject(projectID: String, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = projects.firstIndex(where: { $0.id == projectID }) else { return }

        let previousName = projects[index].name
        projects[index].name = trimmed
        _ = await persistCurrentCache()

        guard !projectID.hasPrefix("local-") else {
            lastErrorMessage = nil
            return
        }

        do {
            try await service.renameProject(projectID: projectID, newName: trimmed)
            lastErrorMessage = nil
        } catch {
            if let currentIndex = projects.firstIndex(where: { $0.id == projectID }) {
                projects[currentIndex].name = previousName
                _ = await persistCurrentCache()
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func renameRoom(roomID: String, projectID: String, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let roomIndex = projects[projectIndex].rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let previousName = projects[projectIndex].rooms[roomIndex].roomType
        updateRoom(roomID: roomID, projectID: projectID, shouldPersist: false) {
            $0.roomType = trimmed
        }
        _ = await persistCurrentCache()

        guard !projectID.hasPrefix("local-"), !roomID.hasPrefix("local-") else {
            lastErrorMessage = nil
            return
        }

        do {
            try await service.renameRoom(roomID: roomID, newName: trimmed)
            lastErrorMessage = nil
        } catch {
            updateRoom(roomID: roomID, projectID: projectID, shouldPersist: false) {
                $0.roomType = previousName
            }
            _ = await persistCurrentCache()
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteProject(projectID: String) async {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let removedProject = projects.remove(at: projectIndex)
        _ = await persistCurrentCache()

        guard !projectID.hasPrefix("local-") else {
            lastErrorMessage = nil
            return
        }

        do {
            try await service.deleteProject(projectID: projectID)
            lastErrorMessage = nil
        } catch {
            let restoredIndex = min(projectIndex, projects.count)
            projects.insert(removedProject, at: restoredIndex)
            _ = await persistCurrentCache()
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteRoom(roomID: String, projectID: String) async {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let roomIndex = projects[projectIndex].rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let removedRoom = projects[projectIndex].rooms.remove(at: roomIndex)
        projects[projectIndex].roomCount = max(0, projects[projectIndex].roomCount - 1)
        _ = await persistCurrentCache()
        await RoomScanAssetService().invalidateCache(forRoomID: roomID)

        guard !projectID.hasPrefix("local-"), !roomID.hasPrefix("local-") else {
            lastErrorMessage = nil
            return
        }

        do {
            try await service.deleteRoom(projectID: projectID, roomID: roomID)
            lastErrorMessage = nil
        } catch {
            if let currentProjectIndex = projects.firstIndex(where: { $0.id == projectID }) {
                let restoredIndex = min(roomIndex, projects[currentProjectIndex].rooms.count)
                projects[currentProjectIndex].rooms.insert(removedRoom, at: restoredIndex)
                projects[currentProjectIndex].roomCount = max(projects[currentProjectIndex].roomCount + 1, projects[currentProjectIndex].rooms.count)
                _ = await persistCurrentCache()
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 업로드 후 로컬 스캔 부가정보(감지 항목 수, 사진 수, 파일명 등)를 채웁니다.
    func recordUploadMetadata(
        roomID: String,
        projectID: String,
        itemCount: Int,
        photoCount: Int,
        fileName: String,
        scanJsonUrl: String?,
        usdzUrl: String?,
        jsonFileName: String?
    ) {
        updateRoom(roomID: roomID, projectID: projectID) { room in
            room.itemCount = itemCount
            room.photoCount = photoCount
            room.fileName = fileName
            room.scanJsonUrl = scanJsonUrl
            room.usdzUrl = usdzUrl
            room.jsonFileName = jsonFileName
            room.uploadedAt = Date()
        }
    }

    func project(withID id: String?) -> SpatiumProject? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    /// 프로젝트별 방 개수를 병렬로 갱신합니다. (순차 N+1 요청 + 건마다 디스크 저장이었던 것을
    /// 동시 요청 + 마지막 1회 저장으로 줄임)
    private func refreshRoomCounts(silently: Bool) async {
        let projectIDs = projects
            .map(\.id)
            .filter { !$0.hasPrefix("local-") }
        guard !projectIDs.isEmpty else { return }

        var firstErrorMessage: String?
        await withTaskGroup(of: (String, Result<Int, Error>).self) { group in
            for projectID in projectIDs {
                group.addTask { [service] in
                    do {
                        return (projectID, .success(try await service.fetchRoomCount(projectID: projectID)))
                    } catch {
                        return (projectID, .failure(error))
                    }
                }
            }
            for await (projectID, result) in group {
                switch result {
                case let .success(count):
                    guard let index = projects.firstIndex(where: { $0.id == projectID }),
                          projects[index].roomCount != count else { continue }
                    projects[index].roomCount = count
                case let .failure(error):
                    if firstErrorMessage == nil, !(error is CancellationError) {
                        firstErrorMessage = error.localizedDescription
                    }
                }
            }
        }
        if let firstErrorMessage {
            if !silently {
                lastErrorMessage = firstErrorMessage
            }
        } else {
            lastErrorMessage = nil
        }
    }

    private func insertRoom(_ room: RoomRecord, projectID: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].rooms.insert(room, at: 0)
        projects[index].roomCount = max(projects[index].roomCount, projects[index].rooms.count)
        scheduleCachePersistence()
    }

    private func updateRoom(
        roomID: String,
        projectID: String,
        shouldPersist: Bool = true,
        mutate: (inout RoomRecord) -> Void
    ) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let roomIndex = projects[projectIndex].rooms.firstIndex(where: { $0.id == roomID }) else { return }
        mutate(&projects[projectIndex].rooms[roomIndex])
        if shouldPersist {
            scheduleCachePersistence()
        }
    }

    private static func newLocalID() -> String {
        "local-\(UUID().uuidString.prefix(8))"
    }

    var localPersistenceErrorMessage: String? {
        cachePersistenceState.failureMessage
    }

    /// 저장 공간·권한 문제를 해결한 뒤 현재 메모리의 최신 프로젝트 목록을 다시 기록한다.
    /// 실패한 시점의 오래된 스냅샷이 아니라 사용자가 계속 작업한 결과 전체를 저장한다.
    @discardableResult
    func retryLocalPersistence() async -> Bool {
        cachePersistenceState = .idle
        return await persistCurrentCache()
    }

    func dismissLocalPersistenceError() {
        guard cachePersistenceState.failureMessage != nil else { return }
        cachePersistenceState = .idle
    }

    private func nextCacheRevision() -> UInt64 {
        cacheRevision += 1
        return cacheRevision
    }

    private func scheduleCachePersistence() {
        let snapshot = projects
        let revision = nextCacheRevision()
        Task { [weak self] in
            guard let self else { return }
            _ = await persistCache(snapshot, revision: revision)
        }
    }

    @discardableResult
    private func persistCurrentCache() async -> Bool {
        let snapshot = projects
        let revision = nextCacheRevision()
        return await persistCache(snapshot, revision: revision)
    }

    private func persistCache(_ snapshot: [SpatiumProject], revision: UInt64) async -> Bool {
        do {
            let result = try await cacheDiskStore.save(snapshot, revision: revision)
            guard revision == cacheRevision else { return true }
            if case let .applied(savedAt) = result {
                cachePersistenceState = .saved(savedAt)
            }
            return true
        } catch {
            guard revision == cacheRevision else { return true }
            recordCachePersistenceFailure(error)
            return false
        }
    }

    private func recordCachePersistenceFailure(_ error: Error) {
        cachePersistenceState = .failed(
            message: "프로젝트 변경 사항을 이 기기에 저장하지 못했어요. 앱을 종료하면 변경 내용이 사라질 수 있습니다. 저장 공간을 확인한 후 다시 시도해 주세요. (\(error.localizedDescription))"
        )
    }
}

private enum ProjectStoreError: LocalizedError {
    case emptyProjectName

    var errorDescription: String? {
        "프로젝트 이름을 입력해 주세요."
    }
}
