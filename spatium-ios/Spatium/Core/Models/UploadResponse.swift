import Foundation

struct UploadResponseData: Decodable {
    var modelId: Int?
    var fileName: String?
    var jsonFileName: String?
}

struct UploadResponse: Decodable {
    var statusCode: Int
    var message: String
    var data: UploadResponseData?
}

enum UploadError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "서버 응답을 확인할 수 없습니다."
        case let .serverError(statusCode, message):
            if let message, !message.isEmpty {
                return "\(statusCode): \(message)"
            }
            return "서버 오류가 발생했습니다. 상태 코드: \(statusCode)"
        }
    }
}
