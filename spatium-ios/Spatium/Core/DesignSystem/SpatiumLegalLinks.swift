import Foundation

/// App Store 심사에는 실제로 열리는 개인정보처리방침/이용약관 URL이 필요합니다.
/// 배포 전 아래 두 주소를 실제 호스팅된 문서 링크로 교체하세요.
enum SpatiumLegalLinks {
    static let privacyPolicyURL = URL(string: "https://spatium.app/privacy")!
    static let termsOfServiceURL = URL(string: "https://spatium.app/terms")!
}
