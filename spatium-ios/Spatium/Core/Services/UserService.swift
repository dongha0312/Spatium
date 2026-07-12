import Foundation

struct UserService {
    private let client = SpatiumAPIClient.shared

    func fetchProfile() async throws -> UserProfile {
        // mock 세션(시뮬레이터 로그인)에서만 로컬 목업 프로필을 사용한다.
        // 실서버 오류를 가짜 프로필로 덮으면 사용자에게 남의 계정처럼 보이므로 그대로 던진다.
        if AuthTokenStore.shared.accessToken?.hasPrefix("mock_") == true {
            return UserProfile(
                userId: "9999",
                email: "test@spatium.com",
                nickname: "테스트 사용자",
                birthDate: nil,
                gender: nil,
                profileImageUrl: nil,
                projectCount: 0,
                placedFurnitureCount: 0
            )
        }
        let envelope: SpatiumAPIEnvelope<UserProfile> = try await client.send(
            method: "GET", path: "/api/users/me"
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        return data
    }

    func updateProfile(_ request: UserUpdateRequest) async throws -> UserProfile {
        let envelope: SpatiumAPIEnvelope<UserProfile> = try await client.send(
            method: "PATCH", path: "/api/users/me", body: request
        )
        guard let data = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        return data
    }

    /// 다른 요청들과 동일하게 액세스 토큰 만료(401) 시 재발급 후 한 번 재시도합니다.
    func uploadAvatar(imageData: Data) async throws -> AvatarUpdateResponseData {
        do {
            return try await uploadAvatarOnce(imageData: imageData)
        } catch let error as SpatiumAPIError {
            guard case .unauthorized = error,
                  let refreshToken = AuthTokenStore.shared.refreshToken, !refreshToken.hasPrefix("mock_") else {
                throw error
            }
            do {
                try await AuthRefreshCoordinator.shared.refreshIfNeeded()
            } catch {
                throw SpatiumAPIError.unauthorized
            }
            return try await uploadAvatarOnce(imageData: imageData)
        }
    }

    private func uploadAvatarOnce(imageData: Data) async throws -> AvatarUpdateResponseData {
        guard let environment = SpatiumAPIEnvironment.shared.baseURL else {
            throw SpatiumAPIError.invalidBaseURL
        }
        var request = URLRequest(url: environment.appendingPathComponent("/api/users/me/avatar"))
        request.httpMethod = "PUT"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = AuthTokenStore.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpatiumAPIError.network(URLError(.badServerResponse))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw SpatiumAPIError.unauthorized }
            throw SpatiumAPIError.network(URLError(.badServerResponse))
        }
        let envelope = try JSONDecoder.spatiumAPI.decode(SpatiumAPIEnvelope<AvatarUpdateResponseData>.self, from: data)
        guard let result = envelope.data else { throw SpatiumAPIError.decoding(URLError(.cannotParseResponse)) }
        return result
    }

    func deleteAvatar() async throws {
        let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
            method: "DELETE", path: "/api/users/me/avatar"
        )
    }

    func deleteAccount() async throws {
        let _: SpatiumAPIEnvelope<EmptyAPIData> = try await client.send(
            method: "DELETE", path: "/api/users/me"
        )
        AuthTokenStore.shared.clear()
    }
}
