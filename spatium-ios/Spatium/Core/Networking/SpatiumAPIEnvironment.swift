import Combine
import Foundation

/// 앱 서버 주소 모음. Debug에서는 숨겨진 개발자 설정으로 주소를 바꿀 수 있지만,
/// Release에서는 이전 개발 설치본의 UserDefaults를 무시하고 배포 주소만 사용합니다.
@MainActor
final class SpatiumAPIEnvironment: ObservableObject {
    static let shared = SpatiumAPIEnvironment()

    private static let storageKey = "spatium.apiBaseURL"
    private static let furnitureAssetStorageKey = "spatium.furnitureAssetBaseURL"
    private static let defaultBaseURL = "http://210.119.12.115:8080"
    private static let defaultFurnitureAssetBaseURL = "http://210.119.12.115:3000"

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
