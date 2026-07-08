import Foundation

/// Every CODEX API response follows this envelope: {"statusCode", "message", "data"}.
struct SpatiumAPIEnvelope<Data: Decodable>: Decodable {
    let statusCode: Int
    let message: String
    let data: Data?
}

/// Placeholder response payload for endpoints whose `data` is always null (logout, delete, etc).
struct EmptyAPIData: Decodable {}
