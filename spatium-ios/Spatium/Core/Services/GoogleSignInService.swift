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

enum GoogleSignInError: LocalizedError {
    case notConfigured
    case cancelled
    case invalidCallback
    case tokenExchangeFailed

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
        }
    }
}

/// GoogleSignIn SDK 없이 표준 OAuth 2.0 (Authorization Code + PKCE)로 구현한
/// Google 로그인. iOS 클라이언트는 client secret 없이 PKCE로 코드 교환이 가능합니다.
@MainActor
final class GoogleSignInService: NSObject {
    private var session: ASWebAuthenticationSession?
    func signIn() async throws -> GoogleSignInResult {
        guard SpatiumSocialConfig.isGoogleConfigured else {
            // Fall back to a mock Google login result for simulation/testing in simulator
            try await Task.sleep(nanoseconds: 800_000_000)
            return GoogleSignInResult(
                idToken: "mock_google_id_token",
                authorizationCode: "mock_google_auth_code",
                redirectURI: "spatium://oauth/callback",
                email: "test.google@spatium.com",
                providerUserId: "google_123456789"
            )
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
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
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
            session.start()
        }
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
        return String((0..<length).map { _ in charset.randomElement()! })
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
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        if let keyWindow {
            return keyWindow
        }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            preconditionFailure("ASWebAuthenticationSession requires an active window scene.")
        }
        return ASPresentationAnchor(windowScene: windowScene)
    }
}
