import Foundation

struct AuthService {
    private let client = SpatiumAPIClient.shared
    private let tokenStore = AuthTokenStore.shared

    /// 개편된 백엔드는 refreshToken을 httpOnly 쿠키(path=/api/auth)로만 내려줍니다.
    /// URLSession이 자동 저장한 쿠키에서 값을 꺼내 키체인에 보관해, 기존 세션 로직을 그대로 유지합니다.
    /// (재발급 API는 "쿠키 우선, 없으면 바디" 폴백을 지원하므로 어느 쪽이든 동작)
    private func resolveRefreshToken(from data: LoginResponseData) -> String {
        if let token = data.refreshToken, !token.isEmpty { return token }
        if let cookieToken = Self.refreshTokenCookieValue() { return cookieToken }
        return tokenStore.refreshToken ?? ""
    }

    private static func refreshTokenCookieValue() -> String? {
        guard let baseURL = SpatiumAPIEnvironment.shared.baseURL else { return nil }
        // 쿠키가 path=/api/auth로 제한돼 있으므로 그 경로 기준으로 조회한다.
        let authURL = baseURL.appendingPathComponent("api/auth/token")
        return HTTPCookieStorage.shared.cookies(for: authURL)?
            .first { $0.name == "refreshToken" && !$0.value.isEmpty }?
            .value
    }

    /// 로그인: POST /api/auth/sessions
    func login(email: String, password: String, keepLogin: Bool = true) async throws -> UserSummary {
        let body = LoginRequest(email: email, password: password, keepLogin: keepLogin)
        let envelope: SpatiumAPIEnvelope<LoginResponseData> = try await client.send(
            method: "POST", path: "/api/auth/sessions", body: body, requiresAuth: false
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        tokenStore.save(AuthTokens(accessToken: data.accessToken, refreshToken: resolveRefreshToken(from: data)))
        return data.user
    }

    /// 회원가입: POST /api/users
    func signUp(
        email: String,
        nickname: String,
        password: String,
        birthDate: String,
        gender: Gender,
        termsAgreed: Bool,
        privacyAgreed: Bool
    ) async throws -> UserSummary {
        let body = SignUpRequest(
            email: email,
            nickname: nickname,
            password: password,
            birthDate: birthDate,
            gender: gender,
            termsAgreed: termsAgreed,
            privacyAgreed: privacyAgreed
        )
        let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
            method: "POST", path: "/api/users", body: body, requiresAuth: false
        )
        return UserSummary(userId: "0", email: email, nickname: nickname, profileImageUrl: nil)
    }

    /// 소셜로그인: POST /api/auth/social-sessions
    /// 성공(200)하면 토큰을 저장하고 사용자 정보를 반환합니다.
    /// 미가입 계정이면 서버가 에러를 내려주며, 호출한 쪽에서 소셜회원가입으로 유도합니다.
    func socialLogin(_ request: SocialLoginRequest) async throws -> UserSummary {
        // 시뮬레이터(mock idToken)에서는 서버 없이 로그인된 것으로 처리.
        if request.idToken.hasPrefix("mock_") {
            try await Task.sleep(nanoseconds: 800_000_000)
            let dummyUser = UserSummary(
                userId: "9999",
                email: request.provider == .apple ? "test.apple@spatium.com" : "test.google@spatium.com",
                nickname: request.provider == .apple ? "Apple 스페이스" : "Google 스페이스",
                profileImageUrl: nil
            )
            tokenStore.save(AuthTokens(accessToken: "mock_access_token", refreshToken: "mock_refresh_token"))
            return dummyUser
        }

        // 실서버 응답을 그대로 따른다. 성공이면 토큰 저장, 실패(미가입 404 등)는 호출부로 전파해
        // 회원가입 유도/에러 표시가 정확히 동작하도록 한다. (가짜 세션을 만들지 않음)
        let envelope: SpatiumAPIEnvelope<LoginResponseData> = try await client.send(
            method: "POST", path: "/api/auth/social-sessions", body: request, requiresAuth: false
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        tokenStore.save(AuthTokens(accessToken: data.accessToken, refreshToken: resolveRefreshToken(from: data)))
        return data.user
    }

    /// 소셜회원가입: POST /api/auth/social-users (토큰 미반환 → 가입 후 다시 소셜로그인 필요)
    func socialSignUp(_ request: SocialSignUpRequest) async throws -> UserSummary {
        // 시뮬레이터(mock idToken)에서는 서버 없이 성공 처리.
        if request.idToken.hasPrefix("mock_") {
            try await Task.sleep(nanoseconds: 800_000_000)
            return UserSummary(userId: "9999", email: "", nickname: request.nickname, profileImageUrl: nil)
        }
        // 실서버에서는 실패를 그대로 전파해야 원인을 알 수 있다. (mock 폴백으로 삼키지 않음)
        let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
            method: "POST", path: "/api/auth/social-users", body: request, requiresAuth: false
        )
        return UserSummary(userId: "0", email: "", nickname: request.nickname, profileImageUrl: nil)
    }

    /// 토큰 재발급: POST /api/auth/token — refreshToken으로 새 access/refresh 쌍을 받아 저장합니다.
    /// (기존 refreshToken은 서버에서 폐기되므로 반드시 새 값으로 갱신해야 합니다.)
    @discardableResult
    func refreshTokens() async throws -> AuthTokens {
        guard let refreshToken = tokenStore.refreshToken, !refreshToken.hasPrefix("mock_") else {
            throw SpatiumAPIError.network(URLError(.userAuthenticationRequired))
        }
        let envelope: SpatiumAPIEnvelope<LoginResponseData> = try await client.send(
            method: "POST", path: "/api/auth/token",
            body: TokenRefreshRequest(refreshToken: refreshToken), requiresAuth: false
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        // rotation된 새 refreshToken도 쿠키로만 오므로 쿠키에서 갱신값을 읽는다.
        let tokens = AuthTokens(accessToken: data.accessToken, refreshToken: resolveRefreshToken(from: data))
        tokenStore.save(tokens)
        return tokens
    }

    /// 로그아웃: DELETE /api/auth/sessions/current (204 No Content)
    func logout() async throws {
        defer {
            tokenStore.clear()
        }
        do {
            let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
                method: "DELETE", path: "/api/auth/sessions/current", requiresAuth: true
            )
        } catch {
            // Ignore server-side logout errors in client to ensure local logout completes
            print("Server logout error: \(error.localizedDescription)")
        }
    }
}
