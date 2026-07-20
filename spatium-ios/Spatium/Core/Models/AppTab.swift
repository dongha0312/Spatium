import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case rooms
    case scan
    case imgTo3D
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "홈"
        case .rooms: "프로젝트"
        case .scan: "스캔"
        case .imgTo3D: "가구 만들기"
        case .settings: "설정"
        }
    }

    var systemImage: String {
        systemImage(selected: false)
    }

    func systemImage(selected: Bool) -> String {
        switch self {
        case .home: selected ? "house.fill" : "house"
        case .rooms: selected ? "folder.fill" : "folder"
        case .scan: "viewfinder"
        case .imgTo3D: selected ? "cube.fill" : "cube"
        case .settings: selected ? "gearshape.fill" : "gearshape"
        }
    }
}
