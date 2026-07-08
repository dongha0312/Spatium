import Foundation

/// A room within a project. `id` is the server's `roomId` (UUID string) once
/// synced; locally-created (not-yet-synced) rooms use a `"local-…"` placeholder id.
struct RoomRecord: Identifiable, Codable {
    var id: String
    var roomType: String
    var itemCount: Int
    var photoCount: Int
    var uploadedAt: Date
    var fileName: String
    var area: Double?
    var scanJsonUrl: String? = nil
    var usdzUrl: String? = nil
    var jsonFileName: String? = nil
    var thumbnailUrl: String? = nil

    var hasScanRenderFiles: Bool {
        renderUSDZReference != nil || renderJSONReference != nil
    }

    var renderUSDZReference: String? {
        firstResolvableReference(usdzUrl, fileName)
    }

    var renderJSONReference: String? {
        firstResolvableReference(scanJsonUrl, jsonFileName)
    }

    private func firstResolvableReference(_ values: String?...) -> String? {
        values.compactMap { value -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return nil }
            return isResolvableFileReference(trimmed) ? trimmed : nil
        }.first
    }

    private func isResolvableFileReference(_ value: String) -> Bool {
        if let url = URL(string: value), url.scheme != nil { return true }
        return value.hasPrefix("/") || value.contains("/")
    }
}
