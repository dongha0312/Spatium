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
    private static let authMethodAccount = "authMethod"

    @Published private(set) var isLoggedIn: Bool

    private init() {
        isLoggedIn = Self.read(account: Self.accessAccount) != nil
    }

    var accessToken: String? {
        Self.read(account: Self.accessAccount)
    }

    var refreshToken: String? {
        Self.read(account: Self.refreshAccount)
    }

    /// 로그인 시점에 저장해 둔 계정 인증 수단. 회원 탈퇴의 본인 재확인 분기에 사용합니다.
    /// (액세스 토큰 JWT/프로필 응답에는 provider 정보가 없어 로그인 경로별로 직접 기록합니다.)
    var authMethod: AccountAuthMethod? {
        guard let raw = Self.read(account: Self.authMethodAccount) else { return nil }
        if raw == "local" { return .local }
        if raw.hasPrefix("social:"),
           let provider = SocialProvider(rawValue: String(raw.dropFirst("social:".count))) {
            return .social(provider)
        }
        return nil
    }

    func saveAuthMethod(_ method: AccountAuthMethod) {
        switch method {
        case .local:
            Self.write("local", account: Self.authMethodAccount)
        case .social(let provider):
            Self.write("social:\(provider.rawValue)", account: Self.authMethodAccount)
        }
    }

    func save(_ tokens: AuthTokens) {
        Self.write(tokens.accessToken, account: Self.accessAccount)
        Self.write(tokens.refreshToken, account: Self.refreshAccount)
        isLoggedIn = true
    }

    func clear() {
        Self.delete(account: Self.accessAccount)
        Self.delete(account: Self.refreshAccount)
        Self.delete(account: Self.authMethodAccount)
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
