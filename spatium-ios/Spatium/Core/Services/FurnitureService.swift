import Foundation

struct FurnitureCatalogResponseItem: Decodable, Equatable {
    struct Dimensions: Codable, Equatable {
        let x: Double
        let y: Double
        let z: Double
    }

    let id: String
    let name: String
    let group: String
    let category: String
    let dimensions: Dimensions
    let modelUrl: String?

    var isUserFurniture: Bool { id.hasPrefix("usr_") }
}

struct FurnitureCreateResponse: Decodable, Equatable {
    let id: String
    let modelUrl: String
}

struct FurnitureCreateMetadata: Encodable, Equatable {
    let nameKr: String
    let name: String
    let category: String
    let categoryKr: String
    let dimensions: FurnitureCatalogResponseItem.Dimensions
}

struct FurnitureService {
    func fetchCatalog() async throws -> [FurnitureCatalogResponseItem] {
        let token = AuthTokenStore.shared.accessToken
        let response: SpatiumAPIEnvelope<[FurnitureCatalogResponseItem]> = try await SpatiumAPIClient.shared.send(
            method: "GET",
            path: "/api/furniture",
            requiresAuth: token != nil && token?.hasPrefix("mock_") == false
        )
        return response.data ?? []
    }

    func fetchUserCatalog() async throws -> [FurnitureCatalogResponseItem] {
        let response: SpatiumAPIEnvelope<[FurnitureCatalogResponseItem]> = try await SpatiumAPIClient.shared.send(
            method: "GET",
            path: "/api/furniture/user"
        )
        return response.data ?? []
    }

    func createUserFurniture(
        modelFileURL: URL,
        fileName: String,
        metadata: FurnitureCreateMetadata
    ) async throws -> FurnitureCreateResponse {
        let metadataData = try JSONEncoder.spatiumAPI.encode(metadata)
        let response: SpatiumAPIEnvelope<FurnitureCreateResponse> = try await SpatiumAPIClient.shared.sendMultipart(
            path: "/api/furniture",
            parts: [
                MultipartFormPart(name: "file", fileURL: modelFileURL, fileName: fileName, contentType: "model/gltf-binary"),
                MultipartFormPart(name: "metadata", data: metadataData, fileName: nil, contentType: "application/json")
            ]
        )
        guard let result = response.data else {
            throw SpatiumAPIError.decoding(URLError(.cannotParseResponse))
        }
        return result
    }

    /// GLB 응답을 URLSession download task로 받아 임시 파일 URL을 반환합니다.
    /// 호출자는 파일을 최종 저장소로 옮기거나 사용 후 삭제해야 합니다.
    func downloadModel(path: String) async throws -> URL {
        if let apiPath = Self.protectedModelAPIPath(
            from: path,
            apiBaseURL: SpatiumAPIEnvironment.shared.baseURL
        ) {
            let response = try await SpatiumAPIClient.shared.downloadFile(
                path: apiPath,
                timeout: 120
            )
            guard Self.fileIsNotEmpty(response.fileURL) else {
                try? FileManager.default.removeItem(at: response.fileURL)
                throw SpatiumAPIError.network(URLError(.zeroByteResource))
            }
            return response.fileURL
        }

        guard let url = resolvedModelURL(path: path) else {
            throw SpatiumAPIError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        // 기본 카탈로그의 /data 에셋은 공개 파일 서버에서 받는다. 보호된 /api 모델은
        // 위의 공통 API 클라이언트만 사용하므로 JWT가 다른 포트나 외부 호스트로 새지 않는다.
        do {
            let (downloadedURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse else {
                try? FileManager.default.removeItem(at: downloadedURL)
                throw SpatiumAPIError.network(URLError(.badServerResponse))
            }
            guard (200..<300).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: downloadedURL)
                throw SpatiumAPIError.server(
                    statusCode: http.statusCode,
                    code: nil,
                    message: "가구 모델을 내려받지 못했습니다. (HTTP \(http.statusCode))"
                )
            }
            guard Self.fileIsNotEmpty(downloadedURL) else {
                try? FileManager.default.removeItem(at: downloadedURL)
                throw SpatiumAPIError.network(URLError(.zeroByteResource))
            }
            let ownedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("furniture-model-\(UUID().uuidString).glb")
            do {
                try FileManager.default.moveItem(at: downloadedURL, to: ownedURL)
            } catch {
                try? FileManager.default.removeItem(at: downloadedURL)
                try? FileManager.default.removeItem(at: ownedURL)
                throw error
            }
            return ownedURL
        } catch let error as SpatiumAPIError {
            throw error
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw SpatiumAPIError.network(error)
        }
    }

    func deleteUserFurniture(id: String) async throws {
        let _: SpatiumAPIEnvelope<String> = try await SpatiumAPIClient.shared.send(
            method: "DELETE",
            path: "/api/furniture/\(id)"
        )
    }

    private func resolvedModelURL(path: String) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        guard let baseURL = SpatiumAPIEnvironment.shared.furnitureAssetBaseURL else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    private static func fileIsNotEmpty(_ url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size > 0
    }

    /// 새 백엔드가 내려주는 사용자 가구 경로(`/api/furniture/{id}/model`)만
    /// 인증·토큰 재발급이 적용되는 Spring API 다운로드로 분류합니다.
    static func protectedModelAPIPath(from value: String, apiBaseURL: URL?) -> String? {
        if value.hasPrefix("/api/furniture/"), value.hasSuffix("/model") {
            return value
        }

        guard let url = URL(string: value),
              url.scheme != nil,
              let apiBaseURL,
              sameOrigin(url, apiBaseURL),
              url.path.hasPrefix("/api/furniture/"),
              url.path.hasSuffix("/model") else {
            return nil
        }
        return url.path
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(of: lhs) == effectivePort(of: rhs)
    }

    private static func effectivePort(of url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }
}
