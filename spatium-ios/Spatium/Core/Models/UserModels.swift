import Foundation

struct UserProfile: Decodable {
    var userId: BackendID
    var email: String
    var nickname: String
    var birthDate: String?
    var gender: Gender?
    var profileImageUrl: String?
    var projectCount: Int?
    var placedFurnitureCount: Int?

    var furnitureCount: Int? { placedFurnitureCount }
}

struct UserUpdateRequest: Encodable {
    var nickname: String?
    var birthDate: String?
    var password: String?
}

struct AvatarUpdateResponseData: Decodable {
    var profileImageUrl: String?
}
