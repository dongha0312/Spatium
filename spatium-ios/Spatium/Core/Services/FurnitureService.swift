import Foundation

struct FurnitureService {
    func fetchCategories() async throws -> [FurnitureCategory] {
        throw URLError(.unsupportedURL)
    }

    func search(categoryID: Int? = nil, keyword: String? = nil, page: Int = 0, size: Int = 30) async throws -> [FurnitureSummary] {
        throw URLError(.unsupportedURL)
    }

    func fetchDetail(furnitureID: Int) async throws -> FurnitureDetail {
        throw URLError(.unsupportedURL)
    }
}
