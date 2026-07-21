import Combine
import Foundation

/// 앱 서버 주소 모음. Debug에서는 숨겨진 개발자 설정으로 주소를 바꿀 수 있지만,
/// Release에서는 이전 개발 설치본의 UserDefaults를 무시하고 배포 주소만 사용합니다.
@MainActor
final class SpatiumAPIEnvironment: ObservableObject {
    static let shared = SpatiumAPIEnvironment()

    private static let storageKey = "spatium.apiBaseURL"
    private static let furnitureAssetStorageKey = "spatium.furnitureAssetBaseURL"
    /// 배포 도메인. Spring API는 `/api/*`, 기본 가구 에셋은 `/data/*`로
    /// 같은 오리진에서 리버스 프록시·정적 서빙됩니다.
    private static let defaultBaseURL = "https://spatium.kro.kr"
    private static let defaultFurnitureAssetBaseURL = "https://spatium.kro.kr"

    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Self.storageKey) }
    }

    @Published var furnitureAssetBaseURLString: String {
        didSet { UserDefaults.standard.set(furnitureAssetBaseURLString, forKey: Self.furnitureAssetStorageKey) }
    }

    private init() {
        #if DEBUG
        baseURLString = UserDefaults.standard.string(forKey: Self.storageKey) ?? Self.defaultBaseURL
        furnitureAssetBaseURLString = UserDefaults.standard.string(forKey: Self.furnitureAssetStorageKey)
            ?? Self.defaultFurnitureAssetBaseURL
        #else
        baseURLString = Self.defaultBaseURL
        furnitureAssetBaseURLString = Self.defaultFurnitureAssetBaseURL
        #endif
    }

    var baseURL: URL? {
        URL(string: baseURLString)
    }

    var furnitureAssetBaseURL: URL? {
        URL(string: furnitureAssetBaseURLString)
    }
}
