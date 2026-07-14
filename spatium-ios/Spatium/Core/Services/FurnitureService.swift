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
        glbData: Data,
        fileName: String,
        metadata: FurnitureCreateMetadata
    ) async throws -> FurnitureCreateResponse {
        let metadataData = try JSONEncoder.spatiumAPI.encode(metadata)
        let response: SpatiumAPIEnvelope<FurnitureCreateResponse> = try await SpatiumAPIClient.shared.sendMultipart(
            path: "/api/furniture",
            parts: [
                MultipartFormPart(name: "file", data: glbData, fileName: fileName, contentType: "model/gltf-binary"),
                MultipartFormPart(name: "metadata", data: metadataData, fileName: nil, contentType: "application/json")
            ]
        )
        guard let result = response.data else {
            throw SpatiumAPIError.decoding(URLError(.cannotParseResponse))
        }
        return result
    }

    func downloadModel(path: String) async throws -> Data {
        guard let url = resolvedModelURL(path: path) else {
            throw SpatiumAPIError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        // 서버가 준 modelUrl이 외부 호스트를 가리켜도 토큰이 새어 나가지 않도록,
        // 우리 서버(API/파일 서버) 호스트일 때만 인증 헤더를 붙인다.
        let trustedHosts = [
            SpatiumAPIEnvironment.shared.baseURL?.host,
            SpatiumAPIEnvironment.shared.furnitureAssetBaseURL?.host
        ].compactMap { $0 }
        if let host = url.host, trustedHosts.contains(host),
           let token = AuthTokenStore.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty else {
                throw SpatiumAPIError.network(URLError(.badServerResponse))
            }
            return data
        } catch let error as SpatiumAPIError {
            throw error
        } catch {
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
}
