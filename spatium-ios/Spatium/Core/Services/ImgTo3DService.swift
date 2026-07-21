import Foundation

struct ImgTo3DSegmentationResult: Equatable {
    let id: String
    let imageData: Data
    let segmentedObject: String
    let translatedQuery: String?
    let confidence: Double?
    let provider: String
}

struct ImgTo3DGenerationResult: Equatable {
    let id: String
    let provider: String
    /// URLSession이 디스크로 스트리밍한 임시 GLB. 호출자가 최종 위치로 옮기거나 삭제합니다.
    let temporaryModelURL: URL
    let fileName: String
}

/// Spring이 바이너리 본문과 함께 전달하는 `X-Spatium-AI-Metadata` 헤더 내용입니다.
/// 헤더 값은 URL-safe Base64로 인코딩된 JSON입니다.
struct ImgTo3DAIMetadata: Decodable, Equatable {
    var provider: String?
    var segmentationProvider: String?
    var segmentedObject: String?
    var translatedQuery: String?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case provider, confidence
        case segmentationProvider = "segmentation_provider"
        case segmentedObject = "segmented_object"
        case translatedQuery = "translated_query"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        segmentationProvider = try container.decodeIfPresent(String.self, forKey: .segmentationProvider)
        segmentedObject = try container.decodeIfPresent(String.self, forKey: .segmentedObject)
        translatedQuery = try container.decodeIfPresent(String.self, forKey: .translatedQuery)
        if let number = try? container.decode(Double.self, forKey: .confidence) {
            confidence = number
        } else if let string = try? container.decode(String.self, forKey: .confidence) {
            confidence = Double(string)
        } else {
            confidence = nil
        }
    }

    static func decodeHeader(_ encoded: String?) -> ImgTo3DAIMetadata? {
        guard var base64 = encoded?.trimmingCharacters(in: .whitespacesAndNewlines),
              !base64.isEmpty else { return nil }
        base64 = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder.spatiumAPI.decode(Self.self, from: data)
    }
}

enum ImgTo3DServiceError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(statusCode: Int, message: String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "API 서버 주소를 확인해주세요."
        case .invalidResponse:
            "이미지 처리 서버 응답을 해석하지 못했습니다."
        case let .server(_, message):
            message
        case .network:
            "API 서버에 연결하지 못했습니다."
        }
    }
}

struct ImgTo3DService {
    static let removeBackgroundPath = "/api/ai/remove-background"
    static let imageTo3DPath = "/api/ai/image-to-3d"

    private static let metadataHeader = "X-Spatium-AI-Metadata"
    private let client = SpatiumAPIClient.shared

    func removeBackground(
        image: ImgTo3DUploadImage.Normalized,
        objectQuery: String,
        provider: ImgTo3DSegmentationProvider = .groundedSAM2
    ) async throws -> ImgTo3DSegmentationResult {
        let mimeType = image.fileExtension.lowercased() == "jpg" ? "image/jpeg" : "image/png"
        var parts = [
            MultipartFormPart(
                name: "image",
                data: image.data,
                fileName: "furniture.\(image.fileExtension)",
                contentType: mimeType
            ),
            textPart(name: "segmentation_provider", value: provider.rawValue)
        ]
        if provider == .groundedSAM2 {
            parts.append(textPart(name: "object_query", value: objectQuery))
        } else {
            parts.append(textPart(name: "target_class", value: "auto"))
        }

        let response = try await sendMultipart(
            path: Self.removeBackgroundPath,
            parts: parts,
            timeout: 120
        )
        guard response.data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
              let metadata = ImgTo3DAIMetadata.decodeHeader(response.header(named: Self.metadataHeader)),
              let segmentedObject = metadata.segmentedObject,
              let segmentationProvider = metadata.segmentationProvider else {
            throw ImgTo3DServiceError.invalidResponse
        }

        return ImgTo3DSegmentationResult(
            id: UUID().uuidString,
            imageData: response.data,
            segmentedObject: segmentedObject,
            translatedQuery: metadata.translatedQuery,
            confidence: metadata.confidence,
            provider: segmentationProvider
        )
    }

    func generateModel(
        segmentedPNG: Data,
        provider: ImgTo3DGenerationProvider = .localTripoSR,
        mcResolution: Int = 256,
        textureResolution: Int = 1024,
        remesh: ImgTo3DRemesh = .none
    ) async throws -> ImgTo3DGenerationResult {
        var parts = [
            MultipartFormPart(name: "image", data: segmentedPNG, fileName: "segmented.png", contentType: "image/png"),
            textPart(name: "provider", value: provider.rawValue),
            textPart(name: "remove_background", value: "false"),
            textPart(name: "foreground_ratio", value: "0.85")
        ]
        if provider == .localStableFast3D {
            parts.append(textPart(name: "texture_resolution", value: String(textureResolution)))
            parts.append(textPart(name: "remesh", value: remesh.rawValue))
        } else {
            parts.append(textPart(name: "mc_resolution", value: String(mcResolution)))
        }

        let response = try await sendMultipartFile(
            path: Self.imageTo3DPath,
            parts: parts,
            timeout: 620
        )
        guard Self.file(response.fileURL, startsWith: Data("glTF".utf8)) else {
            try? FileManager.default.removeItem(at: response.fileURL)
            throw ImgTo3DServiceError.invalidResponse
        }

        let id = UUID().uuidString
        let metadata = ImgTo3DAIMetadata.decodeHeader(response.header(named: Self.metadataHeader))
        return ImgTo3DGenerationResult(
            id: id,
            provider: metadata?.provider ?? provider.rawValue,
            temporaryModelURL: response.fileURL,
            fileName: "\(id).glb"
        )
    }

    private func sendMultipart(
        path: String,
        parts: [MultipartFormPart],
        timeout: TimeInterval
    ) async throws -> SpatiumAPIRawResponse {
        do {
            return try await client.sendMultipartData(path: path, parts: parts, timeout: timeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SpatiumAPIError {
            switch error {
            case .invalidBaseURL:
                throw ImgTo3DServiceError.invalidBaseURL
            case let .network(underlying):
                throw ImgTo3DServiceError.network(underlying)
            case let .server(statusCode, _, message):
                throw ImgTo3DServiceError.server(statusCode: statusCode, message: message)
            case .unauthorized:
                throw ImgTo3DServiceError.server(statusCode: 401, message: "로그인이 필요합니다.")
            case .decoding:
                throw ImgTo3DServiceError.invalidResponse
            }
        }
    }

    private func sendMultipartFile(
        path: String,
        parts: [MultipartFormPart],
        timeout: TimeInterval
    ) async throws -> SpatiumAPITemporaryFileResponse {
        do {
            return try await client.sendMultipartFile(path: path, parts: parts, timeout: timeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SpatiumAPIError {
            switch error {
            case .invalidBaseURL:
                throw ImgTo3DServiceError.invalidBaseURL
            case let .network(underlying):
                throw ImgTo3DServiceError.network(underlying)
            case let .server(statusCode, _, message):
                throw ImgTo3DServiceError.server(statusCode: statusCode, message: message)
            case .unauthorized:
                throw ImgTo3DServiceError.server(statusCode: 401, message: "로그인이 필요합니다.")
            case .decoding:
                throw ImgTo3DServiceError.invalidResponse
            }
        }
    }

    private static func file(_ url: URL, startsWith expected: Data) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: expected.count) else { return false }
        return prefix == expected
    }

    private func textPart(name: String, value: String) -> MultipartFormPart {
        MultipartFormPart(name: name, data: Data(value.utf8), contentType: "text/plain; charset=utf-8")
    }
}
