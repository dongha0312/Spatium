import Combine
import Foundation

/// 로그인한 사용자의 프로필(닉네임/프로필 이미지 등)을 앱 전역에서 공유하기 위한 스토어.
/// 상단 헤더 등 여러 화면이 같은 정보를 구독할 수 있도록 싱글턴으로 둔다.
@MainActor
final class CurrentUserStore: ObservableObject {
    static let shared = CurrentUserStore()

    @Published private(set) var profile: UserProfile?
    @Published private var cachedAvatarSource: String?

    private let service = UserService()
    private let avatarDiskStore = ProfileAvatarSourceDiskStore()
    private var cancellables: Set<AnyCancellable> = []
    private var isRefreshing = false

    private init() {
        if AuthTokenStore.shared.isLoggedIn {
            Task { [weak self] in
                await self?.restoreCachedAvatarIfAvailable()
            }
        }

        // 로그아웃하면 즉시 비우고, 새로 로그인하면 다시 받아온다.
        // (안 그러면 계정을 바꿔 로그인해도 refreshIfNeeded가 이전 프로필을 재사용한다)
        AuthTokenStore.shared.$isLoggedIn
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] loggedIn in
                guard let self else { return }
                if loggedIn {
                    Task {
                        await self.restoreCachedAvatarIfAvailable()
                        await self.refresh()
                    }
                } else {
                    self.clear()
                }
            }
            .store(in: &cancellables)
    }

    /// 표시용 닉네임. 없으면 이메일 앞부분으로 폴백.
    var displayName: String? {
        if let profile {
            if !profile.nickname.isEmpty { return profile.nickname }
            return profile.email.split(separator: "@").first.map(String.init)
        }
        return AuthTokenStore.shared.cachedUserIdentity?.displayName
    }

    /// 백엔드는 일반 URL 또는 data URL(base64)을 내려줄 수 있습니다.
    /// 서버 프로필을 불러온 뒤에는 서버 값(nil 포함)을 우선하고, 로드 전까지만
    /// 같은 사용자의 마지막 디스크 캐시를 사용합니다.
    var avatarSource: String? {
        if let profile {
            return Self.normalizedAvatarSource(profile.profileImageUrl)
        }
        return cachedAvatarSource
    }

    /// 아직 로드된 프로필이 없을 때만 서버에서 받아온다.
    func refreshIfNeeded() async {
        guard profile == nil else { return }
        await refresh()
    }

    /// 서버에서 최신 프로필을 받아온다. 비로그인 상태면 비운다.
    func refresh() async {
        guard AuthTokenStore.shared.isLoggedIn else {
            profile = nil
            return
        }
        guard !isRefreshing else { return }

        let accessToken = AuthTokenStore.shared.accessToken
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let refreshedProfile = try await service.fetchProfile()
            // 로그아웃이나 계정 전환 중 시작된 오래된 응답을 새 세션에 반영하지 않는다.
            guard AuthTokenStore.shared.isLoggedIn,
                  AuthTokenStore.shared.accessToken == accessToken else {
                return
            }
            let refreshedAvatarSource = Self.normalizedAvatarSource(refreshedProfile.profileImageUrl)
            cachedAvatarSource = refreshedAvatarSource
            profile = refreshedProfile
            AuthTokenStore.shared.updateCachedUser(refreshedProfile)
            await avatarDiskStore.save(refreshedAvatarSource, for: refreshedProfile.userId.value)
        } catch is CancellationError {
            return
        } catch {
            // 프로필 갱신은 캐시 보존형 동작이다. 네트워크가 잠시 끊겨도 헤더의
            // 닉네임과 프로필 이미지를 지우지 않고 마지막으로 받은 값을 유지한다.
            return
        }
    }

    /// 로그아웃 등으로 세션이 사라졌을 때 호출.
    func clear() {
        profile = nil
        cachedAvatarSource = nil
        Task { [avatarDiskStore] in
            await avatarDiskStore.clear()
        }
    }

    private func restoreCachedAvatarIfAvailable() async {
        guard profile == nil,
              AuthTokenStore.shared.isLoggedIn,
              let userID = AuthTokenStore.shared.cachedUserIdentity?.userId.value else {
            return
        }

        let restoredSource = await avatarDiskStore.load(for: userID)
        guard profile == nil,
              AuthTokenStore.shared.isLoggedIn,
              AuthTokenStore.shared.cachedUserIdentity?.userId.value == userID else {
            return
        }
        cachedAvatarSource = restoredSource
    }

    private static func normalizedAvatarSource(_ source: String?) -> String? {
        guard let normalized = source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }
}
