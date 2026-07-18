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

    @Published private(set) var isLoggedIn: Bool
    /// API 요청마다 Keychain을 동기 조회하지 않도록 앱 실행 중에는 토큰을 메모리에 유지한다.
    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?
    private var hasLoadedRefreshToken = false

    private init() {
        let storedAccessToken = Self.read(account: Self.accessAccount)
        #if DEBUG
        cachedAccessToken = storedAccessToken
        isLoggedIn = storedAccessToken != nil
        #else
        if storedAccessToken?.hasPrefix("mock_") == true {
            Self.delete(account: Self.accessAccount)
            Self.delete(account: Self.refreshAccount)
            cachedAccessToken = nil
            cachedRefreshToken = nil
            hasLoadedRefreshToken = true
            isLoggedIn = false
        } else {
            cachedAccessToken = storedAccessToken
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

    func save(_ tokens: AuthTokens) {
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
        isLoggedIn = true
    }

    func clear() {
        Self.delete(account: Self.accessAccount)
        Self.delete(account: Self.refreshAccount)
        cachedAccessToken = nil
        cachedRefreshToken = nil
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

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
