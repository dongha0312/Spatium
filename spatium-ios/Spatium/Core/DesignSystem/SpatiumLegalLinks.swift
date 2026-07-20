import Foundation

/// App Store 심사에는 실제로 열리는 개인정보처리방침/이용약관 URL이 필요합니다.
/// 웹 프론트엔드(spatium.kro.kr)의 /privacy·/terms 라우트가 실제 문서를 렌더링합니다.
enum SpatiumLegalLinks {
    static let privacyPolicyURL = URL(string: "https://spatium.kro.kr/privacy")!
    static let termsOfServiceURL = URL(string: "https://spatium.kro.kr/terms")!
}
