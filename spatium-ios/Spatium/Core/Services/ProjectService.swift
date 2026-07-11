import Foundation

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
}

// POST /api/projects → ResponseProjectCreateDTO
private struct CreateProjectResponseData: Decodable {
    var projectId: String
    var projectName: String
}

private struct CreateProjectRequest: Encodable {
    var projectName: String
}

private struct RenameProjectRequest: Encodable {
    var projectId: String
    var projectName: String
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

    // MARK: - 프로젝트

    /// GET /api/projects?page=&size= (JWT). 인증 토큰에서 memId를 추출합니다.
    func fetchProjects() async throws -> [SpatiumProject] {
        let envelope: SpatiumAPIEnvelope<PageResponseData<ProjectListItem>> = try await client.send(
            method: "GET",
            path: "/api/projects",
            query: ["page": "0", "size": "50"]
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        return data.items.map { item in
            SpatiumProject(id: item.projectId, name: item.projectName, roomCount: item.roomCount ?? 0)
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
        let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
            method: "DELETE",
            path: "/api/projects",
            body: ["projectId": projectID]
        )
    }

    /// PATCH /api/projects (JWT) body {projectId, projectName}.
    func renameProject(projectID: String, newName: String) async throws {
        let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
            method: "PATCH",
            path: "/api/projects",
            body: RenameProjectRequest(projectId: projectID, projectName: newName)
        )
    }

    // MARK: - 룸

    /// GET /api/projects/{projectId}/rooms?page=&size= (JWT).
    func fetchRooms(projectID: String) async throws -> [RoomRecord] {
        let envelope: SpatiumAPIEnvelope<PageResponseData<RoomSummaryItem>> = try await client.send(
            method: "GET",
            path: "/api/projects/\(projectID)/rooms",
            query: ["page": "0", "size": "50"]
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        return data.items.map { item in
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
        let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
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
        let envelope: SpatiumAPIEnvelope<RoomSceneData> = try await client.send(
            method: "GET", path: "/api/rooms/\(roomID)/scene"
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }

        let items = data.metadata?.items() ?? []
        let usdzURL = try Self.writeSceneModel(base64: data.model?.dataBase64, roomID: roomID)
        return RoomSceneResult(roomName: data.roomName, items: items, usdzURL: usdzURL)
    }

    /// base64 usdz를 캐시에 파일로 복원해 편집기 메시로 쓸 수 있게 합니다.
    private static func writeSceneModel(base64: String?, roomID: String) throws -> URL? {
        guard let base64, let bytes = Data(base64Encoded: base64) else { return nil }
        let safeID = roomID.replacingOccurrences(of: "/", with: "_")
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomScenes", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("scene-\(safeID).usdz")
        try bytes.write(to: url, options: .atomic)
        return url
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

    /// multipart 요청도 JSON 요청과 동일하게 액세스 토큰 만료(401) 시
    /// 재발급 후 한 번 재시도합니다. (에디터 저장/스캔 업로드가 이 경로를 씁니다)
    private static func sendMultipart<Response: Decodable>(
        path: String,
        textFields: [String: String],
        fileParts: [FilePart]
    ) async throws -> Response {
        do {
            return try await sendMultipartOnce(path: path, textFields: textFields, fileParts: fileParts)
        } catch let error as SpatiumAPIError {
            guard case .unauthorized = error,
                  let refreshToken = await AuthTokenStore.shared.refreshToken, !refreshToken.hasPrefix("mock_") else {
                throw error
            }
            do {
                try await AuthRefreshCoordinator.shared.refreshIfNeeded()
            } catch {
                throw SpatiumAPIError.unauthorized
            }
            return try await sendMultipartOnce(path: path, textFields: textFields, fileParts: fileParts)
        }
    }

    private static func sendMultipartOnce<Response: Decodable>(
        path: String,
        textFields: [String: String],
        fileParts: [FilePart]
    ) async throws -> Response {
        guard let baseURL = await SpatiumAPIEnvironment.shared.baseURL else {
            throw SpatiumAPIError.invalidBaseURL
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = await AuthTokenStore.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        for (name, value) in textFields {
            body.appendMultipartTextField(name: name, value: value, boundary: boundary)
        }
        for part in fileParts {
            try body.appendMultipartField(
                name: part.name,
                fileName: part.url.lastPathComponent,
                contentType: part.contentType,
                fileURL: part.url,
                boundary: boundary
            )
        }
        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SpatiumAPIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SpatiumAPIError.network(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw SpatiumAPIError.unauthorized }
            let message = String(data: responseData, encoding: .utf8) ?? "요청을 처리하지 못했습니다."
            throw SpatiumAPIError.server(statusCode: http.statusCode, code: nil, message: message)
        }

        // 공통 엔벨로프({statusCode,message,data})의 data를 우선 시도하고, 아니면 바디 자체를 디코딩.
        if let envelope = try? JSONDecoder.spatiumAPI.decode(SpatiumAPIEnvelope<Response>.self, from: responseData),
           let data = envelope.data {
            return data
        }
        if let direct = try? JSONDecoder.spatiumAPI.decode(Response.self, from: responseData) {
            return direct
        }
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
