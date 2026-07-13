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
    let modelData: Data
    let fileName: String
}

enum ImgTo3DServiceError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(statusCode: Int, message: String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Image-to-3D 서버 주소를 확인해주세요."
        case .invalidResponse:
            "Image-to-3D 서버 응답을 해석하지 못했습니다."
        case let .server(_, message):
            message
        case .network:
            "Image-to-3D 서버에 연결하지 못했습니다."
        }
    }
}

struct ImgTo3DService {
    private struct SegmentationResponse: Decodable {
        let id: String
        let segmentationProvider: String
        let segmentedObject: String
        let translatedQuery: String?
        let confidence: String?
        let downloadURL: String

        enum CodingKeys: String, CodingKey {
            case id, confidence
            case segmentationProvider = "segmentation_provider"
            case segmentedObject = "segmented_object"
            case translatedQuery = "translated_query"
            case downloadURL = "download_url"
        }
    }

    private struct GenerationResponse: Decodable {
        let id: String
        let provider: String
        let downloadURL: String

        enum CodingKeys: String, CodingKey {
            case id, provider
            case downloadURL = "download_url"
        }
    }

    private var baseURL: URL? { SpatiumAPIEnvironment.shared.imageTo3DBaseURL }

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

        let response: SegmentationResponse = try await postMultipart(path: "/v1/remove-background", parts: parts)
        let imageData = try await download(path: response.downloadURL, timeout: 120)
        return ImgTo3DSegmentationResult(
            id: response.id,
            imageData: imageData,
            segmentedObject: response.segmentedObject,
            translatedQuery: response.translatedQuery,
            confidence: response.confidence.flatMap(Double.init),
            provider: response.segmentationProvider
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

        let response: GenerationResponse = try await postMultipart(
            path: "/v1/image-to-3d",
            parts: parts,
            timeout: 620
        )
        let modelData = try await download(path: response.downloadURL, timeout: 120)
        let fileName = URL(string: response.downloadURL)?.lastPathComponent ?? "\(response.id).glb"
        return ImgTo3DGenerationResult(
            id: response.id,
            provider: response.provider,
            modelData: modelData,
            fileName: fileName
        )
    }

    private func postMultipart<Response: Decodable>(
        path: String,
        parts: [MultipartFormPart],
        timeout: TimeInterval = 120
    ) async throws -> Response {
        guard let url = resolve(path: path) else { throw ImgTo3DServiceError.invalidBaseURL }
        let form = MultipartFormData(parts: parts)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body
        let data = try await perform(request)
        do {
            return try JSONDecoder.spatiumAPI.decode(Response.self, from: data)
        } catch {
            throw ImgTo3DServiceError.invalidResponse
        }
    }

    private func download(path: String, timeout: TimeInterval) async throws -> Data {
        guard let url = resolve(path: path) else { throw ImgTo3DServiceError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw ImgTo3DServiceError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ImgTo3DServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ImgTo3DServiceError.server(
                statusCode: http.statusCode,
                message: Self.errorMessage(from: data, statusCode: http.statusCode)
            )
        }
        return data
    }

    private func resolve(path: String) -> URL? {
        guard let baseURL else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    private func textPart(name: String, value: String) -> MultipartFormPart {
        MultipartFormPart(name: name, data: Data(value.utf8), contentType: "text/plain; charset=utf-8")
    }

    private static func errorMessage(from data: Data, statusCode: Int) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] else {
            return fallbackMessage(for: statusCode)
        }
        if let message = detail as? String { return message }
        if let dictionary = detail as? [String: Any] {
            return dictionary["message"] as? String ?? fallbackMessage(for: statusCode)
        }
        return fallbackMessage(for: statusCode)
    }

    private static func fallbackMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 413: "이미지는 10MB 이하여야 합니다."
        case 415: "PNG 또는 JPEG 이미지를 사용해주세요."
        case 422: "사진에서 요청한 가구를 찾지 못했거나 입력값이 올바르지 않습니다."
        case 502: "3D 모델 실행에 실패했습니다."
        case 503: "서버의 이미지 처리 모델이 준비되지 않았습니다."
        case 504: "이미지 처리 시간이 초과되었습니다."
        default: "Image-to-3D 요청을 처리하지 못했습니다."
        }
    }
}
