import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case rooms
    case scan
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "홈"
        case .rooms: "공간"
        case .scan: "스캔"
        case .settings: "설정"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .rooms: "square.grid.2x2"
        case .scan: "camera.viewfinder"
        case .settings: "gearshape"
        }
    }
}
