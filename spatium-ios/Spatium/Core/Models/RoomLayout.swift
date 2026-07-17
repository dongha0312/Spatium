import Foundation

nonisolated enum RoomViewMode: String, Codable, CaseIterable, Sendable {
    case threeD = "3D"
    case skyView = "SKYVIEW"
    /// 방 안에서 눈높이로 둘러보는 1인칭 뷰. 앱 전용 모드라 서버에는 동기화하지 않는다.
    case person = "PERSON"

    var title: String {
        switch self {
        case .threeD: "3D"
        case .skyView: "스카이뷰"
        case .person: "1인칭"
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

nonisolated struct FurnitureTransform: Codable, Equatable, Sendable {
    nonisolated struct Vector3: Codable, Equatable, Sendable {
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

nonisolated struct RoomSpace: Codable, Identifiable, Equatable, Sendable {
    var spaceId: String
    var name: String
    var area: Double
    var ceilingHeight: Double
    var wallColor: String
    /// 스캔 metadata의 _spatiumFloorColor에서 복원한 선택 바닥 색상.
    /// nil이면 스캔 원본 재질(박스 방은 기본 바닥색)을 유지합니다.
    var floorColor: String? = nil

    var id: String { spaceId }
}

/// 꾸미기 책장 위에 올려놓은 피규어(소품) 하나. 프런트엔드 `decorationToJson` 대응.
/// position은 부모 가구(바닥 중심 pivot) 로컬 좌표계 기준이라, 책장을 옮기거나 돌려도
/// 상대 배치가 그대로 유지된다.
nonisolated struct PlacedDecoration: Codable, Identifiable, Equatable, Sendable {
    var decorId: Int
    var name: String
    /// 렌더할 GLB 파일명(확장자 제외). 번들 모델 또는 사용자 가구(usr_) 파일명.
    var modelName: String?
    /// 배치 시점에 0.35m 이하로 정규화된 기준 치수(m).
    var width: Double
    var height: Double
    var depth: Double
    /// 부모 가구 로컬 좌표(피규어 바닥 중심).
    var position: FurnitureTransform.Vector3
    /// 부모 기준 Y 회전(라디안).
    var rotationY: Double
    /// 크기 슬라이더의 균일 스케일. 표시 크기 = 기준 치수 × scale.
    var scale: Double = 1

    var id: Int { decorId }
}

nonisolated struct PlacedFurniture: Codable, Identifiable, Equatable, Sendable {
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
    /// 꾸미기 책장 위에 올려둔 피규어들. 일반 가구는 nil/빈 배열.
    var decorations: [PlacedDecoration]? = nil

    var id: Int { itemId }
}

nonisolated struct RoomLayout: Codable, Equatable, Sendable {
    var roomId: String
    var roomName: String
    var viewMode: RoomViewMode?
    var space: RoomSpace?
    var furnitures: [PlacedFurniture]
}
