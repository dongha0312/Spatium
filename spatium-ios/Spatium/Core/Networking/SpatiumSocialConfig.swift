import Foundation

/// 소셜 로그인 클라이언트 설정.
///
/// Google 로그인을 실제로 동작시키려면 Google Cloud Console에서
/// iOS용 OAuth 클라이언트 ID를 발급받아 `googleClientID`에 넣어야 합니다.
/// (APIs & Services → Credentials → Create OAuth client ID → iOS,
///  Bundle ID: name.dongharyu.Spatium)
enum SpatiumSocialConfig {
    static let googleClientID = "75882144038-c0nfcrirlhlod41gl8esi8rtbne5gj4t.apps.googleusercontent.com"

    /// Apple 네이티브 로그인은 리다이렉트가 없지만, 서버 소셜로그인 요청에 필요한
    /// 고정 콜백 값입니다. (명세 예시: spatium://oauth/callback)
    static let appleRedirectURI = "spatium://oauth/callback"

    static var isGoogleConfigured: Bool {
        !googleClientID.hasPrefix("YOUR_")
    }

    /// iOS 네이티브 OAuth 콜백은 클라이언트 ID를 뒤집은 커스텀 스킴을 사용합니다.
    static var googleRedirectURI: String {
        let reversed = googleClientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(reversed):/oauth2redirect"
    }

    static var googleCallbackScheme: String {
        let reversed = googleClientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(reversed)"
    }
}
