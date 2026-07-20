import Foundation

enum SpatiumAPIError: LocalizedError {
    case invalidBaseURL
    case network(Error)
    case decoding(Error)
    /// 서버 공통 에러 응답: {statusCode, code, message, errors[]}
    case server(statusCode: Int, code: String?, message: String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "서버 주소를 확인해 주세요."
        case .network:
            return "서버에 연결할 수 없습니다. 네트워크 상태를 확인해 주세요."
        case .decoding:
            return "서버 응답을 해석할 수 없습니다."
        case let .server(_, _, message):
            return message
        case .unauthorized:
            return "로그인이 필요합니다."
        }
    }

    /// 서버가 내려준 에러 코드(예: SOCIAL_USER_NOT_FOUND). 분기 처리에 사용합니다.
    var serverCode: String? {
        if case let .server(_, code, _) = self { return code }
        return nil
    }
}

/// 공통 에러 응답 바디.
private struct SpatiumAPIErrorBody: Decodable {
    var statusCode: Int?
    var code: String?
    var message: String?
}

/// JSON 엔벨로프가 아닌 파일 응답을 위한 공통 결과입니다.
/// AI 생성물과 보호된 사용자 가구 모델처럼 본문 자체가 데이터인 API에서 사용합니다.
struct SpatiumAPIRawResponse {
    let data: Data
    let httpResponse: HTTPURLResponse

    func header(named name: String) -> String? {
        httpResponse.value(forHTTPHeaderField: name)
    }
}

/// 큰 바이너리 응답을 메모리 Data 대신 임시 파일로 전달합니다.
/// 호출자는 파일을 최종 위치로 옮기거나 사용 후 삭제해야 합니다.
struct SpatiumAPITemporaryFileResponse {
    let fileURL: URL
    let httpResponse: HTTPURLResponse

    func header(named name: String) -> String? {
        httpResponse.value(forHTTPHeaderField: name)
    }
}

extension JSONEncoder {
    static let spatiumAPI: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let spatiumAPI: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// 401 발생 시 토큰 재발급이 동시에 여러 번 나가 refresh rotation이 꼬이지 않도록
/// 한 번에 하나의 갱신만 실행하는 직렬화 장치. 진행 중이면 그 결과를 함께 기다립니다.
actor AuthRefreshCoordinator {
    static let shared = AuthRefreshCoordinator()
    private var inFlight: Task<AuthTokens, Error>?

    func refreshIfNeeded() async throws {
        if let inFlight {
            _ = try await inFlight.value
            return
        }
        let task = Task { try await AuthService().refreshTokens() }
        inFlight = task
        defer { inFlight = nil }
        _ = try await task.value
    }
}

/// Spring API 공통 클라이언트. 일반 API의 `{statusCode, message, data}` 엔벨로프와
/// AI·모델 다운로드의 바이너리 응답이 인증 및 토큰 재발급 흐름을 공유합니다.
struct SpatiumAPIClient {
    static let shared = SpatiumAPIClient()

    private var environment: SpatiumAPIEnvironment { SpatiumAPIEnvironment.shared }
    private var tokenStore: AuthTokenStore { AuthTokenStore.shared }

    @discardableResult
    func send<ResponseData: Decodable>(
        method: String,
        path: String,
        query: [String: String] = [:],
        requiresAuth: Bool = true
    ) async throws -> SpatiumAPIEnvelope<ResponseData> {
        try await sendResolvingAuth(requiresAuth: requiresAuth) {
            try makeRequest(method: method, path: path, query: query, requiresAuth: requiresAuth)
        }
    }

    @discardableResult
    func send<Body: Encodable, ResponseData: Decodable>(
        method: String,
        path: String,
        query: [String: String] = [:],
        body: Body,
        requiresAuth: Bool = true
    ) async throws -> SpatiumAPIEnvelope<ResponseData> {
        try await sendResolvingAuth(requiresAuth: requiresAuth) {
            var request = try makeRequest(method: method, path: path, query: query, requiresAuth: requiresAuth)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.spatiumAPI.encode(body)
            return request
        }
    }

    @discardableResult
    func sendMultipart<ResponseData: Decodable>(
        method: String = "POST",
        path: String,
        parts: [MultipartFormPart],
        requiresAuth: Bool = true,
        timeout: TimeInterval = 120
    ) async throws -> SpatiumAPIEnvelope<ResponseData> {
        // 바디는 임시 파일로 만들어 스트리밍 업로드한다. 대용량 USDZ/GLB를
        // 메모리에 통째로 올리지 않고, 바디 작성(파일 읽기)도 메인 스레드를 막지 않는다.
        let boundary = "Spatium-\(UUID().uuidString)"
        let bodyFileURL = try await Task.detached {
            try MultipartFormData.writeBodyFile(parts: parts, boundary: boundary)
        }.value
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }

        return try await sendResolvingAuth(requiresAuth: requiresAuth, uploadingFile: bodyFileURL) {
            var request = try makeRequest(method: method, path: path, query: [:], requiresAuth: requiresAuth)
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = timeout
            return request
        }
    }

    /// Spring API가 JSON 엔벨로프 대신 파일 본문을 직접 반환하는 요청을 보냅니다.
    /// 인증 만료 시에도 일반 API와 동일하게 토큰을 재발급하고 한 번 재시도합니다.
    func sendData(
        method: String = "GET",
        path: String,
        query: [String: String] = [:],
        requiresAuth: Bool = true,
        timeout: TimeInterval = 120
    ) async throws -> SpatiumAPIRawResponse {
        try await sendResolvingAuthData(requiresAuth: requiresAuth) {
            var request = try makeRequest(
                method: method,
                path: path,
                query: query,
                requiresAuth: requiresAuth
            )
            request.timeoutInterval = timeout
            return request
        }
    }

    /// Spring API의 큰 바이너리 본문을 URLSession 임시 파일로 내려받습니다.
    /// 인증 만료 시에도 임시 파일을 정리한 뒤 토큰을 갱신해 한 번 재시도합니다.
    func downloadFile(
        method: String = "GET",
        path: String,
        query: [String: String] = [:],
        requiresAuth: Bool = true,
        timeout: TimeInterval = 120
    ) async throws -> SpatiumAPITemporaryFileResponse {
        try await sendResolvingAuthFile(requiresAuth: requiresAuth) {
            var request = try makeRequest(
                method: method,
                path: path,
                query: query,
                requiresAuth: requiresAuth
            )
            request.timeoutInterval = timeout
            return request
        }
    }

    /// 멀티파트를 스트리밍 업로드하고 바이너리 응답을 그대로 돌려줍니다.
    func sendMultipartData(
        method: String = "POST",
        path: String,
        parts: [MultipartFormPart],
        requiresAuth: Bool = true,
        timeout: TimeInterval = 120
    ) async throws -> SpatiumAPIRawResponse {
        let boundary = "Spatium-\(UUID().uuidString)"
        let bodyFileURL = try await Task.detached {
            try MultipartFormData.writeBodyFile(parts: parts, boundary: boundary)
        }.value
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }

        return try await sendResolvingAuthData(requiresAuth: requiresAuth, uploadingFile: bodyFileURL) {
            var request = try makeRequest(method: method, path: path, query: [:], requiresAuth: requiresAuth)
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = timeout
            return request
        }
    }

    /// 멀티파트 요청 바디와 큰 바이너리 응답을 모두 파일 기반으로 처리합니다.
    /// URLSession download task에 임시 바디 파일의 InputStream을 연결해 GLB 응답을 Data로 합치지 않습니다.
    func sendMultipartFile(
        method: String = "POST",
        path: String,
        parts: [MultipartFormPart],
        requiresAuth: Bool = true,
        timeout: TimeInterval = 120
    ) async throws -> SpatiumAPITemporaryFileResponse {
        let boundary = "Spatium-\(UUID().uuidString)"
        let bodyFileURL = try await Task.detached {
            try MultipartFormData.writeBodyFile(parts: parts, boundary: boundary)
        }.value
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }

        return try await sendResolvingAuthFile(requiresAuth: requiresAuth, uploadingFile: bodyFileURL) {
            var request = try makeRequest(method: method, path: path, query: [:], requiresAuth: requiresAuth)
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = timeout
            return request
        }
    }

    /// 요청을 보내고, 액세스 토큰 만료(401)면 refreshToken으로 재발급 후 한 번 재시도합니다.
    /// 재발급 자체가 거부되면(세션 만료) 토큰을 비워 로그인 화면으로 돌아가게 합니다.
    private func sendResolvingAuth<ResponseData: Decodable>(
        requiresAuth: Bool,
        uploadingFile bodyFileURL: URL? = nil,
        makeRequest: () throws -> URLRequest
    ) async throws -> SpatiumAPIEnvelope<ResponseData> {
        do {
            let response = try await performData(try makeRequest(), uploadingFile: bodyFileURL)
            return try decodeEnvelope(response)
        } catch let error as SpatiumAPIError {
            guard requiresAuth, case .unauthorized = error,
                  let refreshToken = tokenStore.refreshToken, !refreshToken.hasPrefix("mock_") else {
                throw error
            }
            do {
                try await AuthRefreshCoordinator.shared.refreshIfNeeded()
            } catch let refreshError as SpatiumAPIError {
                if case .unauthorized = refreshError {
                    tokenStore.clear()
                }
                throw SpatiumAPIError.unauthorized
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SpatiumAPIError.unauthorized
            }
            // 새 액세스 토큰으로 요청을 다시 만들어 한 번만 재시도.
            let response = try await performData(try makeRequest(), uploadingFile: bodyFileURL)
            return try decodeEnvelope(response)
        }
    }

    /// 바이너리 API도 엔벨로프 API와 같은 인증 재시도 규칙을 공유합니다.
    private func sendResolvingAuthData(
        requiresAuth: Bool,
        uploadingFile bodyFileURL: URL? = nil,
        makeRequest: () throws -> URLRequest
    ) async throws -> SpatiumAPIRawResponse {
        do {
            return try await performData(try makeRequest(), uploadingFile: bodyFileURL)
        } catch let error as SpatiumAPIError {
            guard requiresAuth, case .unauthorized = error,
                  let refreshToken = tokenStore.refreshToken, !refreshToken.hasPrefix("mock_") else {
                throw error
            }
            do {
                try await AuthRefreshCoordinator.shared.refreshIfNeeded()
            } catch let refreshError as SpatiumAPIError {
                if case .unauthorized = refreshError {
                    tokenStore.clear()
                }
                throw SpatiumAPIError.unauthorized
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SpatiumAPIError.unauthorized
            }
            return try await performData(try makeRequest(), uploadingFile: bodyFileURL)
        }
    }

    /// 파일 응답에서도 일반 API와 같은 401 재발급 규칙을 유지합니다.
    private func sendResolvingAuthFile(
        requiresAuth: Bool,
        uploadingFile bodyFileURL: URL? = nil,
        makeRequest: () throws -> URLRequest
    ) async throws -> SpatiumAPITemporaryFileResponse {
        do {
            return try await performFile(try makeRequest(), uploadingFile: bodyFileURL)
        } catch let error as SpatiumAPIError {
            guard requiresAuth, case .unauthorized = error,
                  let refreshToken = tokenStore.refreshToken, !refreshToken.hasPrefix("mock_") else {
                throw error
            }
            do {
                try await AuthRefreshCoordinator.shared.refreshIfNeeded()
            } catch let refreshError as SpatiumAPIError {
                if case .unauthorized = refreshError {
                    tokenStore.clear()
                }
                throw SpatiumAPIError.unauthorized
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SpatiumAPIError.unauthorized
            }
            return try await performFile(try makeRequest(), uploadingFile: bodyFileURL)
        }
    }

    private func makeRequest(method: String, path: String, query: [String: String], requiresAuth: Bool) throws -> URLRequest {
        guard let baseURL = environment.baseURL else {
            throw SpatiumAPIError.invalidBaseURL
        }
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SpatiumAPIError.invalidBaseURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw SpatiumAPIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        // 2초는 셀룰러/혼잡한 망에서 정상 요청도 끊어버린다. 연결 거부는 어차피 즉시 실패하므로
        // 타임아웃은 응답 없는 서버를 걸러낼 정도면 충분하다.
        request.timeoutInterval = 10.0
        request.httpMethod = method

        if requiresAuth, let token = tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func performData(
        _ request: URLRequest,
        uploadingFile bodyFileURL: URL? = nil
    ) async throws -> SpatiumAPIRawResponse {
        let data: Foundation.Data
        let response: URLResponse
        do {
            if let bodyFileURL {
                (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyFileURL)
            } else {
                (data, response) = try await URLSession.shared.data(for: request)
            }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw SpatiumAPIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpatiumAPIError.network(URLError(.badServerResponse))
        }

        // 상태 코드 검사가 빈 바디 처리보다 먼저다. 순서가 반대면 바디 없는 401/5xx가
        // 성공 엔벨로프로 둔갑해 토큰 재발급·낙관적 업데이트 롤백이 전부 건너뛰어진다.
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw SpatiumAPIError.unauthorized
            }
            let errorBody = try? JSONDecoder.spatiumAPI.decode(SpatiumAPIErrorBody.self, from: data)
            throw SpatiumAPIError.server(
                statusCode: httpResponse.statusCode,
                code: errorBody?.code,
                message: errorBody?.message ?? "요청을 처리하지 못했습니다."
            )
        }

        return SpatiumAPIRawResponse(data: data, httpResponse: httpResponse)
    }

    /// download task가 응답을 디스크에 기록하게 하고, 멀티파트 요청일 때는 바디도 파일 스트림으로 공급합니다.
    private func performFile(
        _ originalRequest: URLRequest,
        uploadingFile bodyFileURL: URL? = nil
    ) async throws -> SpatiumAPITemporaryFileResponse {
        var request = originalRequest
        if let bodyFileURL {
            do {
                let size = try bodyFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, let stream = InputStream(url: bodyFileURL) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                request.httpBodyStream = stream
                request.setValue(String(size), forHTTPHeaderField: "Content-Length")
            } catch {
                throw SpatiumAPIError.network(error)
            }
        }

        let downloadedURL: URL
        let response: URLResponse
        do {
            (downloadedURL, response) = try await URLSession.shared.download(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw SpatiumAPIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw SpatiumAPIError.network(URLError(.badServerResponse))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = Self.decodeErrorBody(from: downloadedURL)
            try? FileManager.default.removeItem(at: downloadedURL)
            if httpResponse.statusCode == 401 {
                throw SpatiumAPIError.unauthorized
            }
            throw SpatiumAPIError.server(
                statusCode: httpResponse.statusCode,
                code: errorBody?.code,
                message: errorBody?.message ?? "요청을 처리하지 못했습니다."
            )
        }

        let ownedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatium-response-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.moveItem(at: downloadedURL, to: ownedURL)
        } catch {
            try? FileManager.default.removeItem(at: downloadedURL)
            try? FileManager.default.removeItem(at: ownedURL)
            throw SpatiumAPIError.network(error)
        }
        return SpatiumAPITemporaryFileResponse(fileURL: ownedURL, httpResponse: httpResponse)
    }

    /// 비정상 응답은 백엔드 JSON 에러 바디만 필요하므로 최대 64KiB까지만 읽습니다.
    private static func decodeErrorBody(from fileURL: URL) -> SpatiumAPIErrorBody? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1_024),
              !data.isEmpty else { return nil }
        return try? JSONDecoder.spatiumAPI.decode(SpatiumAPIErrorBody.self, from: data)
    }

    private func decodeEnvelope<ResponseData: Decodable>(
        _ response: SpatiumAPIRawResponse
    ) throws -> SpatiumAPIEnvelope<ResponseData> {
        let data = response.data
        let httpResponse = response.httpResponse

        if httpResponse.statusCode == 204 || data.isEmpty {
            return SpatiumAPIEnvelope(statusCode: httpResponse.statusCode, message: "", data: nil)
        }

        guard let envelope = try? JSONDecoder.spatiumAPI.decode(SpatiumAPIEnvelope<ResponseData>.self, from: data) else {
            throw SpatiumAPIError.decoding(URLError(.cannotParseResponse))
        }

        return envelope
    }
}
