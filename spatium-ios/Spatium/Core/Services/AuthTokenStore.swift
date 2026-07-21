import Combine
import Foundation
import Security

struct AuthTokens {
    var accessToken: String
    var refreshToken: String
}

/// Stores JWT tokens in the Keychain (not UserDefaults) so they survive
/// reinstalls the way users expect and aren't readable via a file dump.
@MainActor
final class AuthTokenStore: ObservableObject {
    static let shared = AuthTokenStore()

    private static let service = "com.spatium.auth"
    private static let accessAccount = "accessToken"
    private static let refreshAccount = "refreshToken"
    private static let userIdentityAccount = "currentUserIdentity"

    @Published private(set) var isLoggedIn: Bool
    /// 로그인/프로필 응답에서 받은 최소 사용자 정보. 토큰과 함께 Keychain에 저장해
    /// 앱 재실행 직후 헤더가 네트워크 응답 전에도 닉네임을 표시할 수 있게 합니다.
    @Published private(set) var cachedUserIdentity: CachedUserIdentity?
    /// API 요청마다 Keychain을 동기 조회하지 않도록 앱 실행 중에는 토큰을 메모리에 유지한다.
    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?
    private var hasLoadedRefreshToken = false

    private init() {
        let storedAccessToken = Self.read(account: Self.accessAccount)
        let storedUserIdentity = storedAccessToken.flatMap { _ in Self.readUserIdentity() }
        #if DEBUG
        cachedAccessToken = storedAccessToken
        cachedUserIdentity = storedUserIdentity
        isLoggedIn = storedAccessToken != nil
        #else
        if storedAccessToken?.hasPrefix("mock_") == true {
            Self.delete(account: Self.accessAccount)
            Self.delete(account: Self.refreshAccount)
            Self.delete(account: Self.userIdentityAccount)
            cachedAccessToken = nil
            cachedRefreshToken = nil
            cachedUserIdentity = nil
            hasLoadedRefreshToken = true
            isLoggedIn = false
        } else {
            cachedAccessToken = storedAccessToken
            cachedUserIdentity = storedUserIdentity
            isLoggedIn = storedAccessToken != nil
        }
        #endif
    }

    var accessToken: String? {
        cachedAccessToken
    }

    var refreshToken: String? {
        if !hasLoadedRefreshToken {
            cachedRefreshToken = Self.read(account: Self.refreshAccount)
            hasLoadedRefreshToken = true
        }
        return cachedRefreshToken
    }

    func save(_ tokens: AuthTokens, user: UserSummary) {
        #if !DEBUG
        guard !tokens.accessToken.hasPrefix("mock_"), !tokens.refreshToken.hasPrefix("mock_") else {
            clear()
            return
        }
        #endif
        Self.write(tokens.accessToken, account: Self.accessAccount)
        Self.write(tokens.refreshToken, account: Self.refreshAccount)
        cachedAccessToken = tokens.accessToken
        cachedRefreshToken = tokens.refreshToken
        hasLoadedRefreshToken = true
        updateCachedUser(user)
        isLoggedIn = true
    }

    /// 프로필 편집이나 서버 새로고침으로 닉네임이 바뀌면 재실행용 캐시도 함께 갱신합니다.
    func updateCachedUser(_ profile: UserProfile) {
        updateCachedUserIdentity(CachedUserIdentity(profile: profile))
    }

    private func updateCachedUser(_ user: UserSummary) {
        updateCachedUserIdentity(CachedUserIdentity(user: user))
    }

    private func updateCachedUserIdentity(_ identity: CachedUserIdentity) {
        guard let data = try? JSONEncoder().encode(identity),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }
        Self.write(encoded, account: Self.userIdentityAccount)
        cachedUserIdentity = identity
    }

    func clear() {
        Self.delete(account: Self.accessAccount)
        Self.delete(account: Self.refreshAccount)
        Self.delete(account: Self.userIdentityAccount)
        cachedAccessToken = nil
        cachedRefreshToken = nil
        cachedUserIdentity = nil
        hasLoadedRefreshToken = true
        isLoggedIn = false
    }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let valueAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, valueAttributes as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return }

        let attributes = query.merging(valueAttributes) { _, newValue in newValue }
        // 첫 잠금 해제 후 접근 가능 + 이 기기 전용: 백업/기기 이전으로 세션 토큰이
        // 다른 기기로 복사되지 않게 한다. (재설치 시 유지되는 동작은 그대로)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func readUserIdentity() -> CachedUserIdentity? {
        guard let encoded = read(account: userIdentityAccount),
              let data = encoded.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(CachedUserIdentity.self, from: data)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
