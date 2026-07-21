import Foundation

enum Gender: Codable {
    case male
    case female

    private var backendValue: String {
        switch self {
        case .male: "0"
        case .female: "1"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            switch value {
            case 0: self = .male
            case 1: self = .female
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported gender value: \(value)")
            }
            return
        }

        let value = try container.decode(String.self).uppercased()
        switch value {
        case "0", "MALE", "M":
            self = .male
        case "1", "FEMALE", "F":
            self = .female
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported gender value: \(value)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(backendValue)
    }
}

enum SocialProvider: String, Codable {
    case apple = "APPLE"
    case google = "GOOGLE"
    case kakao = "KAKAO"
}

/// 로그인: POST /api/auth/sessions
struct LoginRequest: Encodable {
    var email: String
    var password: String
    var keepLogin: Bool
}

/// 회원가입: POST /api/users
struct SignUpRequest: Encodable {
    var email: String
    var nickname: String
    var password: String
    var birthDate: String
    var gender: Gender
    var termsAgreed: Bool
    var privacyAgreed: Bool
}

/// 소셜로그인: POST /api/auth/social-sessions
/// 보안 강화 후 서버가 idToken(JWT)을 직접 검증해 email/sub를 얻으므로, 앱은 provider와 idToken만 보냅니다.
struct SocialLoginRequest: Encodable {
    var provider: SocialProvider
    var idToken: String
}

/// 소셜회원가입: POST /api/auth/social-users
/// email/providerUserId는 서버가 idToken 검증으로 직접 얻으므로 보내지 않습니다.
struct SocialSignUpRequest: Encodable {
    var provider: SocialProvider
    var idToken: String
    var nickname: String
    var birthDate: String
    var gender: Gender
    var termsAgreed: Bool
    var privacyAgreed: Bool
}

/// 토큰 재발급: POST /api/auth/token (refreshToken으로 새 access/refresh 쌍 발급)
struct TokenRefreshRequest: Encodable {
    var refreshToken: String
}

/// 서버가 ID를 문자열(memId) 또는 숫자로 내려줘도 안전하게 문자열로 디코딩하는 래퍼.
/// 백엔드의 userId는 mem_id(문자열)이며, 숫자형으로 바뀌어도 그대로 파싱됩니다.
struct BackendID: Codable, Hashable, CustomStringConvertible, ExpressibleByStringLiteral {
    let value: String

    init(_ value: String) { self.value = value }
    init(stringLiteral value: String) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(Int(double))
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    var description: String { value }
}

/// 공통 사용자 요약(UserSummaryResponse).
struct UserSummary: Decodable {
    var userId: BackendID
    var email: String
    var nickname: String
    var profileImageUrl: String?
}

/// 앱 재실행 직후에도 헤더가 서버 응답을 기다리지 않고 로그인 사용자를 표시하기 위한
/// 최소 캐시입니다. 프로필 이미지(data URL일 수 있음)와 생년월일 등은 저장하지 않습니다.
struct CachedUserIdentity: Codable, Equatable {
    var userId: BackendID
    var email: String
    var nickname: String

    init(user: UserSummary) {
        userId = user.userId
        email = user.email
        nickname = user.nickname
    }

    init(profile: UserProfile) {
        userId = profile.userId
        email = profile.email
        nickname = profile.nickname
    }

    var displayName: String? {
        if !nickname.isEmpty { return nickname }
        return email.split(separator: "@").first.map(String.init)
    }
}

/// 로그인/소셜로그인 성공 응답(LoginResponse).
struct LoginResponseData: Decodable {
    var accessToken: String
    /// 개편된 백엔드는 refreshToken을 응답 바디 대신 httpOnly 쿠키로만 내려줍니다(바디는 null).
    /// 구버전 서버 호환을 위해 옵셔널로 두고, 없으면 쿠키에서 읽습니다.
    var refreshToken: String?
    var tokenType: String
    var expiresIn: Int
    var user: UserSummary
}
