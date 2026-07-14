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

    private init() {
        let storedAccessToken = Self.read(account: Self.accessAccount)
        #if DEBUG
        isLoggedIn = storedAccessToken != nil
        #else
        if storedAccessToken?.hasPrefix("mock_") == true {
            Self.delete(account: Self.accessAccount)
            Self.delete(account: Self.refreshAccount)
            isLoggedIn = false
        } else {
            isLoggedIn = storedAccessToken != nil
        }
        #endif
    }

    var accessToken: String? {
        Self.read(account: Self.accessAccount)
    }

    var refreshToken: String? {
        Self.read(account: Self.refreshAccount)
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
        isLoggedIn = true
    }

    func clear() {
        Self.delete(account: Self.accessAccount)
        Self.delete(account: Self.refreshAccount)
        isLoggedIn = false
    }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        // 첫 잠금 해제 후 접근 가능 + 이 기기 전용: 백업/기기 이전으로 세션 토큰이
        // 다른 기기로 복사되지 않게 한다. (재설치 시 유지되는 동작은 그대로)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
