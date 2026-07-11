import Foundation

struct FurnitureCategory: Decodable, Identifiable {
    var categoryId: Int
    var name: String

    var id: Int { categoryId }
}

struct FurnitureSummary: Decodable, Identifiable {
    var furnitureId: Int
    var name: String
    var brand: String?
    var price: Int?
    var thumbnailUrl: String?
    var categoryId: Int?

    var id: Int { furnitureId }
}

struct FurnitureDetail: Decodable, Identifiable {
    var furnitureId: Int
    var name: String
    var brand: String?
    var price: Int?
    var width: Double?
    var depth: Double?
    var height: Double?
    var thumbnailUrl: String?
    var modelUrl: String?
    /// 번들 GLB 파일명(확장자 제외). 로컬 카탈로그에서 고른 가구가 어떤 3D 모델로
    /// 렌더될지 지정한다. 서버 응답에는 없는 필드라 nil일 수 있다.
    var modelName: String?

    var id: Int { furnitureId }
}

struct FurnitureSearchResult: Decodable {
    var items: [FurnitureSummary]
    var page: Int?
    var size: Int?
    var totalElements: Int?
    var totalPages: Int?
    var hasNext: Bool?
}

struct FurnitureCategoryListResponse: Decodable {
    var items: [FurnitureCategory]
}
