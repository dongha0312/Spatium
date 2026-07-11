import Foundation

enum RoomViewMode: String, Codable, CaseIterable {
    case threeD = "3D"
    case skyView = "SKYVIEW"
    /// 방 안에서 눈높이로 둘러보는 1인칭 뷰. 앱 전용 모드라 서버에는 동기화하지 않는다.
    case person = "PERSON"

    var title: String {
        switch self {
        case .threeD: "3D"
        case .skyView: "스카이뷰"
        case .person: "사람 뷰"
        }
    }

    var systemImage: String {
        switch self {
        case .threeD: "rotate.3d"
        case .skyView: "square.grid.3x3.topleft.filled"
        case .person: "figure.stand"
        }
    }
}

struct FurnitureTransform: Codable, Equatable {
    struct Vector3: Codable, Equatable {
        var x: Double
        var y: Double
        var z: Double

        static let zero = Vector3(x: 0, y: 0, z: 0)
        static let one = Vector3(x: 1, y: 1, z: 1)
    }

    var position: Vector3
    var rotation: Vector3
    var scale: Vector3

    static let identity = FurnitureTransform(position: .zero, rotation: .zero, scale: .one)
}

struct RoomSpace: Codable, Identifiable {
    var spaceId: String
    var name: String
    var area: Double
    var ceilingHeight: Double
    var wallColor: String

    var id: String { spaceId }
}

struct PlacedFurniture: Codable, Identifiable {
    var itemId: Int
    var furnitureId: Int
    var furnitureName: String
    var position: FurnitureTransform.Vector3
    var rotation: FurnitureTransform.Vector3
    var scale: FurnitureTransform.Vector3
    var width: Double?
    var depth: Double?
    var height: Double?
    /// 선택한 정확한 GLB 파일명(확장자 제외). nil이면 카테고리 기본 모델을 사용합니다.
    var modelName: String? = nil

    var id: Int { itemId }
}

struct RoomLayout: Codable {
    var roomId: String
    var roomName: String
    var viewMode: RoomViewMode?
    var space: RoomSpace?
    var furnitures: [PlacedFurniture]
}
