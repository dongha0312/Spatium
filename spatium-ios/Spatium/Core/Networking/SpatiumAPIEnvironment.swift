import Combine
import Foundation

/// Holds the CODEX server base URL (host only, no path). The hidden developer
/// settings sheet edits this directly; every service builds full paths off it.
@MainActor
final class SpatiumAPIEnvironment: ObservableObject {
    static let shared = SpatiumAPIEnvironment()

    private static let storageKey = "spatium.apiBaseURL"
    private static let defaultBaseURL = "http://210.119.12.115:8080"

    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Self.storageKey) }
    }

    private init() {
        baseURLString = UserDefaults.standard.string(forKey: Self.storageKey) ?? Self.defaultBaseURL
    }

    var baseURL: URL? {
        URL(string: baseURLString)
    }
}

