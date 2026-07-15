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

    /// 클라이언트 공통 multipart 경로를 쓰므로 401 재발급 재시도도 동일하게 처리됩니다.
    func uploadAvatar(imageData: Data) async throws -> AvatarUpdateResponseData {
        let envelope: SpatiumAPIEnvelope<AvatarUpdateResponseData> = try await client.sendMultipart(
            method: "PUT",
            path: "/api/users/me/avatar",
            parts: [
                MultipartFormPart(
                    name: "image",
                    data: imageData,
                    fileName: "avatar.jpg",
                    contentType: "image/jpeg"
                )
            ]
        )
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
