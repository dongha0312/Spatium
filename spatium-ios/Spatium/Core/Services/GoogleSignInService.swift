import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Google 계정 인증 결과. 서버 `/api/auth/social-sessions` 요청에 사용됩니다.
struct GoogleSignInResult {
    var idToken: String
    var authorizationCode: String
    var redirectURI: String
    var email: String?
    var providerUserId: String?
}

enum GoogleSignInError: LocalizedError, Equatable {
    case notConfigured
    case cancelled
    case invalidCallback
    case tokenExchangeFailed
    case presentationUnavailable
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google 로그인 설정이 아직 완료되지 않았습니다."
        case .cancelled:
            return "Google 로그인이 취소되었습니다."
        case .invalidCallback:
            return "Google 인증 응답을 처리할 수 없습니다."
        case .tokenExchangeFailed:
            return "Google 토큰 교환에 실패했습니다."
        case .presentationUnavailable:
            return "Google 로그인 화면을 표시할 수 없습니다. 앱으로 돌아온 뒤 다시 시도해 주세요."
        case .failedToStart:
            return "Google 로그인 창을 열지 못했습니다. 잠시 후 다시 시도해 주세요."
        }
    }
}

/// GoogleSignIn SDK 없이 표준 OAuth 2.0 (Authorization Code + PKCE)로 구현한
/// Google 로그인. iOS 클라이언트는 client secret 없이 PKCE로 코드 교환이 가능합니다.
@MainActor
final class GoogleSignInService: NSObject {
    typealias PresentationAnchorProvider = @MainActor () -> ASPresentationAnchor?

    private var session: ASWebAuthenticationSession?
    /// 인증 세션 동안 실제 앱 윈도우를 유지해 presentation context 요청 시 같은 윈도우를 반환한다.
    private var retainedPresentationAnchor: ASPresentationAnchor?
    private let presentationAnchorProvider: PresentationAnchorProvider

    init(
        presentationAnchorProvider: @escaping PresentationAnchorProvider = {
            GoogleSignInService.activePresentationAnchor()
        }
    ) {
        self.presentationAnchorProvider = presentationAnchorProvider
        super.init()
    }

    func signIn() async throws -> GoogleSignInResult {
        guard SpatiumSocialConfig.isGoogleConfigured else {
            #if DEBUG
            // Fall back to a mock Google login result for simulation/testing in simulator
            try await Task.sleep(nanoseconds: 800_000_000)
            return GoogleSignInResult(
                idToken: "mock_google_id_token",
                authorizationCode: "mock_google_auth_code",
                redirectURI: "spatium://oauth/callback",
                email: "test.google@spatium.com",
                providerUserId: "google_123456789"
            )
            #else
            throw GoogleSignInError.notConfigured
            #endif
        }

        let codeVerifier = Self.randomURLSafeString(length: 64)
        let codeChallenge = Self.sha256Base64URL(codeVerifier)
        let state = Self.randomURLSafeString(length: 24)
        let redirectURI = SpatiumSocialConfig.googleRedirectURI

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SpatiumSocialConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        let callbackURL = try await authenticate(url: components.url!, callbackScheme: SpatiumSocialConfig.googleCallbackScheme)

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleSignInError.invalidCallback
        }

        let idToken = try await exchangeCode(code, codeVerifier: codeVerifier, redirectURI: redirectURI)

        return GoogleSignInResult(
            idToken: idToken,
            authorizationCode: code,
            redirectURI: redirectURI,
            email: JWTClaims.email(from: idToken),
            providerUserId: JWTClaims.subject(from: idToken)
        )
    }

    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        // presentationAnchor(for:)는 오류를 던질 수 없으므로 세션 시작 전에 먼저 검증한다.
        retainedPresentationAnchor = try presentationAnchorForAuthentication()

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                self?.session = nil
                self?.retainedPresentationAnchor = nil

                if let error {
                    if case ASWebAuthenticationSessionError.canceledLogin = error {
                        continuation.resume(throwing: GoogleSignInError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleSignInError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            // start()가 실패하면 completion이 영영 불리지 않아 await가 멈추고
            // 로그인 버튼이 잠긴다. 즉시 에러로 재개한다.
            if !session.start() {
                self.session = nil
                self.retainedPresentationAnchor = nil
                continuation.resume(throwing: GoogleSignInError.failedToStart)
            }
        }
    }

    /// 활성 앱 윈도우가 없는 화면 전환·백그라운드 상태를 복구 가능한 로그인 오류로 변환한다.
    func presentationAnchorForAuthentication() throws -> ASPresentationAnchor {
        guard let anchor = presentationAnchorProvider() else {
            throw GoogleSignInError.presentationUnavailable
        }
        return anchor
    }

    private static func activePresentationAnchor() -> ASPresentationAnchor? {
        let activeScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        for scene in activeScenes {
            if let keyWindow = scene.windows.first(where: \.isKeyWindow) {
                return keyWindow
            }
            if let visibleWindow = scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 }) {
                return visibleWindow
            }
        }
        return nil
    }

    private func exchangeCode(_ code: String, codeVerifier: String, redirectURI: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "client_id": SpatiumSocialConfig.googleClientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = object["id_token"] as? String else {
            throw GoogleSignInError.tokenExchangeFailed
        }
        return idToken
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(length: Int) -> String {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard length > 0, !charset.isEmpty else { return "" }
        return String((0..<length).map { _ in charset[Int.random(in: charset.indices)] })
    }

    private static func sha256Base64URL(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleSignInService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // authenticate()에서 선행 검증 후 보관하므로 정상 경로에서는 항상 앱 윈도우가 존재한다.
        // 프레임워크가 예상 밖의 시점에 다시 요청하더라도 강제 종료하지 않도록 안전한 기본값을 반환한다.
        retainedPresentationAnchor
            ?? Self.activePresentationAnchor()
            ?? ASPresentationAnchor(frame: .zero)
    }
}
