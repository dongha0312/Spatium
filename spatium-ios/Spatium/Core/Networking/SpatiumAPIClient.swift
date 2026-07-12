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

/// Thin client for the CODEX backend. Every endpoint returns the same
/// {statusCode, message, data} envelope, so callers just specify the path,
/// method, and expected `data` payload type.
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
            request.httpBody = try? JSONEncoder.spatiumAPI.encode(body)
            return request
        }
    }

    /// 요청을 보내고, 액세스 토큰 만료(401)면 refreshToken으로 재발급 후 한 번 재시도합니다.
    /// 재발급 자체가 거부되면(세션 만료) 토큰을 비워 로그인 화면으로 돌아가게 합니다.
    private func sendResolvingAuth<ResponseData: Decodable>(
        requiresAuth: Bool,
        makeRequest: () throws -> URLRequest
    ) async throws -> SpatiumAPIEnvelope<ResponseData> {
        do {
            return try await perform(try makeRequest())
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
            } catch {
                throw SpatiumAPIError.unauthorized
            }
            // 새 액세스 토큰으로 요청을 다시 만들어 한 번만 재시도.
            return try await perform(try makeRequest())
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

    private func perform<ResponseData: Decodable>(_ request: URLRequest) async throws -> SpatiumAPIEnvelope<ResponseData> {
        let data: Foundation.Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SpatiumAPIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpatiumAPIError.network(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 204 || data.isEmpty {
            return SpatiumAPIEnvelope(statusCode: httpResponse.statusCode, message: "", data: nil)
        }

        // 에러 상태 코드는 {statusCode, code, message, errors} 형태이므로 먼저 처리합니다.
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = try? JSONDecoder.spatiumAPI.decode(SpatiumAPIErrorBody.self, from: data)
            if httpResponse.statusCode == 401 {
                throw SpatiumAPIError.unauthorized
            }
            throw SpatiumAPIError.server(
                statusCode: httpResponse.statusCode,
                code: errorBody?.code,
                message: errorBody?.message ?? "요청을 처리하지 못했습니다."
            )
        }

        guard let envelope = try? JSONDecoder.spatiumAPI.decode(SpatiumAPIEnvelope<ResponseData>.self, from: data) else {
            throw SpatiumAPIError.decoding(URLError(.cannotParseResponse))
        }

        return envelope
    }
}
