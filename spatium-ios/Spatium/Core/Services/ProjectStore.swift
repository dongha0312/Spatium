import Combine
import Foundation
import SwiftUI

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [SpatiumProject] = []
    @Published var lastErrorMessage: String?

    private let service = ProjectService()
    private let cacheFileURL: URL
    private var cancellables: Set<AnyCancellable> = []

    init(cacheFileURL: URL? = nil) {
        self.cacheFileURL = cacheFileURL ?? Self.defaultCacheFileURL()
        // 캐시는 로그인 세션 전용: 게스트/비로그인에게 이전 계정의 프로젝트를 보여주지 않는다.
        projects = AuthTokenStore.shared.isLoggedIn ? loadCache() : []

        // 로그아웃하면 이전 계정 데이터가 다음 사용자에게 남지 않도록 캐시를 비운다.
        AuthTokenStore.shared.$isLoggedIn
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] loggedIn in
                guard let self else { return }
                if loggedIn {
                    Task { await self.refresh() }
                } else {
                    self.clearLocalData()
                }
            }
            .store(in: &cancellables)

        Task { await refresh() }
    }

    /// 로그아웃/계정 전환 시 메모리와 디스크 캐시를 모두 비운다.
    private func clearLocalData() {
        projects = []
        lastErrorMessage = nil
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    private static func defaultCacheFileURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("projects.json")
    }

    /// 서버에서 최신 프로젝트 목록을 받아옵니다. 실패 시 기존(캐시/로컬)을 유지합니다.
    func refresh() async {
        guard AuthTokenStore.shared.isLoggedIn else { return }
        do {
            projects = try await service.fetchProjects()
            lastErrorMessage = nil
            saveCache()
            await refreshRoomCounts()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createProject(name: String) async -> SpatiumProject {
        do {
            let created = try await service.createProject(name: name)
            projects.insert(created, at: 0)
            lastErrorMessage = nil
            saveCache()
            return created
        } catch {
            lastErrorMessage = error.localizedDescription
            let local = SpatiumProject(id: Self.newLocalID(), name: name)
            projects.insert(local, at: 0)
            saveCache()
            return local
        }
    }

    /// 스캔 직후 즉시 UI에 보여줄 **로컬** 룸을 만듭니다. (서버 룸은 업로드 시점에 생성)
    @discardableResult
    func registerLocalRoom(projectID: String, roomName: String, area: Double) -> RoomRecord {
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
        saveCache()
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
        saveCache()
    }

    func loadRooms(projectID: String) async {
        guard !projectID.hasPrefix("local-") else { return }
        do {
            let rooms = try await service.fetchRooms(projectID: projectID)
            guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
            projects[index].rooms = rooms
            projects[index].roomCount = rooms.count
            lastErrorMessage = nil
            saveCache()
            // 목록 API에는 항목 수가 없으므로, 각 방의 스캔 JSON에서 실제 개수를 받아 채운다.
            await refreshItemCounts(projectID: projectID, rooms: rooms)
        } catch {
            lastErrorMessage = error.localizedDescription
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
                updateRoom(roomID: roomID, projectID: projectID) { $0.itemCount = count }
            }
        }
    }

    func renameProject(projectID: String, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = projects.firstIndex(where: { $0.id == projectID }) else { return }

        projects[index].name = trimmed
        saveCache()

        guard !projectID.hasPrefix("local-") else {
            lastErrorMessage = nil
            return
        }

        do {
            try await service.renameProject(projectID: projectID, newName: trimmed)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func renameRoom(roomID: String, projectID: String, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        updateRoom(roomID: roomID, projectID: projectID) { $0.roomType = trimmed }

        guard !projectID.hasPrefix("local-"), !roomID.hasPrefix("local-") else {
            lastErrorMessage = nil
            return
        }

        do {
            try await service.renameRoom(roomID: roomID, newName: trimmed)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteRoom(roomID: String, projectID: String) async {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let roomIndex = projects[projectIndex].rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let removedRoom = projects[projectIndex].rooms.remove(at: roomIndex)
        projects[projectIndex].roomCount = max(0, projects[projectIndex].roomCount - 1)
        saveCache()
        RoomScanAssetService().invalidateCache(forRoomID: roomID)

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
                saveCache()
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

    func deleteProjects(at offsets: IndexSet) {
        projects.remove(atOffsets: offsets)
        saveCache()
    }

    private func refreshRoomCounts() async {
        let projectIDs = projects
            .map(\.id)
            .filter { !$0.hasPrefix("local-") }

        for projectID in projectIDs {
            do {
                let count = try await service.fetchRoomCount(projectID: projectID)
                guard let index = projects.firstIndex(where: { $0.id == projectID }) else { continue }
                projects[index].roomCount = count
                lastErrorMessage = nil
                saveCache()
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func insertRoom(_ room: RoomRecord, projectID: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].rooms.insert(room, at: 0)
        projects[index].roomCount = max(projects[index].roomCount, projects[index].rooms.count)
        saveCache()
    }

    private func updateRoom(roomID: String, projectID: String, mutate: (inout RoomRecord) -> Void) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let roomIndex = projects[projectIndex].rooms.firstIndex(where: { $0.id == roomID }) else { return }
        mutate(&projects[projectIndex].rooms[roomIndex])
        saveCache()
    }

    private static func newLocalID() -> String {
        "local-\(UUID().uuidString.prefix(8))"
    }

    private func loadCache() -> [SpatiumProject] {
        guard let data = try? Data(contentsOf: cacheFileURL) else { return [] }
        return (try? JSONDecoder.spatiumAPI.decode([SpatiumProject].self, from: data)) ?? []
    }

    private func saveCache() {
        guard let data = try? JSONEncoder.spatiumAPI.encode(projects) else { return }
        try? data.write(to: cacheFileURL, options: .atomic)
    }
}
