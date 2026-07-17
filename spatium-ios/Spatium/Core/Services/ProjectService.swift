import Foundation
import OSLog

// MARK: - 백엔드 응답 DTO (공통 페이지 래퍼)

private struct PageResponseData<Item: Decodable>: Decodable {
    var items: [Item]
    var page: Int?
    var size: Int?
    var totalElements: Int?
    var totalPages: Int?
    var hasNext: Bool?
}

// GET /api/projects → PageResponseDTO<ResponseProjectListDTO>
private struct ProjectListItem: Decodable {
    var projectId: String
    var projectName: String
    var roomCount: Int?
    var furnitureCount: Int?
    var createdAt: String?
}

// POST /api/projects → ResponseProjectCreateDTO
private struct CreateProjectResponseData: Decodable {
    var projectId: String
    var projectName: String
}

private struct CreateProjectRequest: Encodable {
    var projectName: String
}

/// 서버가 base64로 내려준 USDZ를 메인 스레드 밖에서 캐시 파일로 복원한다.
/// 직렬 큐를 사용해 같은 방을 동시에 열더라도 atomic 교체 작업이 서로 겹치지 않게 한다.
nonisolated final class RoomSceneModelDiskStore: @unchecked Sendable {
    private let directoryURL: URL
    private let operationObserver: (@Sendable (Bool) -> Void)?
    private let queue = DispatchQueue(
        label: "com.spatium.room-scene-model-disk-store",
        qos: .utility
    )

    init(
        directoryURL: URL? = nil,
        operationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomScenes", isDirectory: true)
        self.operationObserver = operationObserver
    }

    func materialize(base64: String?, roomID: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    operationObserver?(Thread.isMainThread)
                    guard let base64, let bytes = Data(base64Encoded: base64) else {
                        continuation.resume(returning: nil)
                        return
                    }

                    try FileManager.default.createDirectory(
                        at: directoryURL,
                        withIntermediateDirectories: true
                    )
                    let safeID = roomID.replacingOccurrences(of: "/", with: "_")
                    let fileURL = directoryURL.appendingPathComponent("scene-\(safeID).usdz")
                    try bytes.write(to: fileURL, options: .atomic)
                    continuation.resume(returning: fileURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// GET /api/projects/{id}/rooms → PageResponseDTO<ResponseRoomSummaryDTO>
private struct RoomSummaryItem: Decodable {
    var roomId: String
    var roomName: String
    var area: String?
    var thumbnailUrl: String?
    var updatedAt: String?
}

// POST /api/projects/{id}/rooms → ResponseRoomCreateDTO
private struct CreateRoomResponseData: Decodable {
    var roomId: String
    var roomName: String
}

struct ProjectService {
    private let client = SpatiumAPIClient.shared
    nonisolated private static let roomSceneModelDiskStore = RoomSceneModelDiskStore()

    // MARK: - 프로젝트

    /// 페이지당 항목 수와, 폭주 방지를 위한 최대 페이지 수(50 × 20 = 1,000개).
    private static let pageSize = 50
    private static let maxPages = 20

    /// hasNext를 따라 전 페이지를 수집합니다. (50개 고정 조회는 51번째 항목부터 조용히 사라졌음)
    private func fetchAllPages<Item: Decodable>(path: String) async throws -> [Item] {
        var items: [Item] = []
        var page = 0
        while true {
            let envelope: SpatiumAPIEnvelope<PageResponseData<Item>> = try await client.send(
                method: "GET",
                path: path,
                query: ["page": "\(page)", "size": "\(Self.pageSize)"]
            )
            guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
            items += data.items
            guard data.hasNext == true, !data.items.isEmpty, page < Self.maxPages - 1 else { break }
            page += 1
        }
        return items
    }

    /// GET /api/projects?page=&size= (JWT). 인증 토큰에서 memId를 추출합니다.
    func fetchProjects() async throws -> [SpatiumProject] {
        let items: [ProjectListItem] = try await fetchAllPages(path: "/api/projects")
        return items.map { item in
            SpatiumProject(
                id: item.projectId,
                name: item.projectName,
                createdAt: item.createdAt.flatMap(Self.parseDate) ?? Date(),
                roomCount: item.roomCount ?? 0
            )
        }
    }

    /// POST /api/projects (JWT) body {projectName}.
    func createProject(name: String) async throws -> SpatiumProject {
        let envelope: SpatiumAPIEnvelope<CreateProjectResponseData> = try await client.send(
            method: "POST",
            path: "/api/projects",
            body: CreateProjectRequest(projectName: name)
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        return SpatiumProject(id: data.projectId, name: data.projectName)
    }

    /// DELETE /api/projects (JWT) body {projectId}.
    func deleteProject(projectID: String) async throws {
        let _: SpatiumAPIEnvelope<String> = try await client.send(
            method: "DELETE",
            path: "/api/projects",
            body: ["projectId": projectID]
        )
    }

    /// PATCH /api/projects/{projectId} (JWT) body {projectName}.
    func renameProject(projectID: String, newName: String) async throws {
        let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
            method: "PATCH",
            path: "/api/projects/\(projectID)",
            body: ["projectName": newName]
        )
    }

    // MARK: - 룸

    /// GET /api/projects/{projectId}/rooms?page=&size= (JWT).
    func fetchRooms(projectID: String) async throws -> [RoomRecord] {
        let items: [RoomSummaryItem] = try await fetchAllPages(path: "/api/projects/\(projectID)/rooms")
        return items.map { item in
            RoomRecord(
                id: item.roomId,
                roomType: item.roomName,
                itemCount: 0,
                photoCount: 0,
                uploadedAt: item.updatedAt.flatMap(Self.parseDate) ?? Date(),
                fileName: "",
                area: item.area.flatMap(Double.init),
                thumbnailUrl: item.thumbnailUrl
            )
        }
    }

    /// GET /api/projects/{projectId}/rooms?page=0&size=1 의 totalElements로 방 개수만 빠르게 확인합니다.
    func fetchRoomCount(projectID: String) async throws -> Int {
        let envelope: SpatiumAPIEnvelope<PageResponseData<RoomSummaryItem>> = try await client.send(
            method: "GET",
            path: "/api/projects/\(projectID)/rooms",
            query: ["page": "0", "size": "1"]
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        return data.totalElements ?? data.items.count
    }

    /// POST /api/projects/{projectId}/rooms (JWT, multipart).
    /// roomName(폼필드) + metadata(JSON 파일) + file(usdz)를 실어 룸을 생성합니다.
    func createRoom(projectID: String, roomName: String, metadataURL: URL, usdzURL: URL) async throws -> RoomRecord {
        let data: CreateRoomResponseData = try await Self.sendMultipart(
            path: "/api/projects/\(projectID)/rooms",
            textFields: ["roomName": roomName],
            fileParts: [
                FilePart(name: "metadata", url: metadataURL, contentType: "application/json"),
                FilePart(name: "file", url: usdzURL, contentType: "model/vnd.usdz+zip")
            ]
        )
        return RoomRecord(
            id: data.roomId,
            roomType: data.roomName,
            itemCount: 0,
            photoCount: 0,
            uploadedAt: Date(),
            fileName: usdzURL.lastPathComponent
        )
    }

    /// POST /api/rooms/save (JWT, multipart). 3D 에디터에서 수정한 룸 메타데이터를 저장합니다.
    /// area는 선택값(백엔드 `area` 폼필드, required=false).
    func saveEditedRoom(projectID: String, roomID: String, area: Double? = nil, metadataURL: URL) async throws {
        var textFields = ["projectId": projectID, "roomId": roomID]
        if let area {
            textFields["area"] = String(area)
        }
        let _: EmptyMultipartResponse = try await Self.sendMultipart(
            path: "/api/rooms/save",
            textFields: textFields,
            fileParts: [FilePart(name: "metadata", url: metadataURL, contentType: "application/json")]
        )
    }

    /// DELETE /api/rooms (JWT) body {projectId, roomId}.
    func deleteRoom(projectID: String, roomID: String) async throws {
        let _: SpatiumAPIEnvelope<String> = try await client.send(
            method: "DELETE",
            path: "/api/rooms",
            body: ["projectId": projectID, "roomId": roomID]
        )
    }

    /// PATCH /api/rooms/{roomId} (JWT) body {roomName}. (projectId는 경로/토큰으로 식별하므로 보내지 않음)
    func renameRoom(roomID: String, newName: String) async throws {
        let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
            method: "PATCH",
            path: "/api/rooms/\(roomID)",
            body: ["roomName": newName]
        )
    }

    // MARK: - 룸 3D 씬 (저장된 룸 다시 불러오기)

    /// GET /api/rooms/{roomId}/scene → 저장된 metadata(편집 확정본) + usdz(base64)를 받아
    /// 편집기에 바로 올릴 수 있는 형태로 변환합니다.
    struct RoomSceneResult {
        var roomName: String
        var items: [EditableScanItem]
        var usdzURL: URL?
        var floorColor: String?
    }

    private struct RoomSceneData: Decodable {
        struct Model: Decodable {
            var fileName: String?
            var contentType: String?
            var dataBase64: String?
        }
        var roomId: String
        var roomName: String
        var metadata: RoomPlanExportJSON?
        var model: Model?
    }

    func fetchRoomScene(roomID: String) async throws -> RoomSceneResult {
        let signposter = PerformanceSignposts.roomScene
        let envelope: SpatiumAPIEnvelope<RoomSceneData> = try await {
            let downloadInterval = signposter.beginInterval("roomScene.download", id: signposter.makeSignpostID())
            defer { signposter.endInterval("roomScene.download", downloadInterval) }
            return try await client.send(method: "GET", path: "/api/rooms/\(roomID)/scene")
        }()
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }

        let items = data.metadata?.items() ?? []
        let materializeInterval = signposter.beginInterval("roomScene.materialize", id: signposter.makeSignpostID())
        defer { signposter.endInterval("roomScene.materialize", materializeInterval) }
        let usdzURL = try await Self.roomSceneModelDiskStore.materialize(
            base64: data.model?.dataBase64,
            roomID: roomID
        )
        return RoomSceneResult(
            roomName: data.roomName,
            items: items,
            usdzURL: usdzURL,
            floorColor: data.metadata?.floorColor
        )
    }

    // MARK: - Multipart 전송 공통

    private struct FilePart {
        let name: String
        let url: URL
        let contentType: String
    }

    /// 응답 data를 사용하지 않는 multipart 요청용 더미.
    private struct EmptyMultipartResponse: Decodable {
        init(from decoder: Decoder) throws {}
    }

    /// multipart 전송은 SpatiumAPIClient로 일원화한다. 401 재발급 재시도, 120초 업로드
    /// 타임아웃, 파일 스트리밍(메모리 미적재)을 클라이언트가 공통으로 처리한다.
    private static func sendMultipart<Response: Decodable>(
        path: String,
        textFields: [String: String],
        fileParts: [FilePart]
    ) async throws -> Response {
        var parts = textFields.map { MultipartFormPart(name: $0.key, data: Data($0.value.utf8)) }
        parts += fileParts.map { MultipartFormPart(name: $0.name, fileURL: $0.url, contentType: $0.contentType) }
        let envelope: SpatiumAPIEnvelope<Response> = try await SpatiumAPIClient.shared.sendMultipart(
            path: path, parts: parts
        )
        if let data = envelope.data { return data }
        // data가 비어 있는 성공 응답(저장 등): 빈 객체로 표현 가능한 타입이면 성공으로 처리.
        if let empty = try? JSONDecoder.spatiumAPI.decode(Response.self, from: Data("{}".utf8)) { return empty }
        throw SpatiumAPIError.decoding(URLError(.cannotParseResponse))
    }

    private static let dateParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseDate(_ string: String) -> Date? {
        if let date = dateParser.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
