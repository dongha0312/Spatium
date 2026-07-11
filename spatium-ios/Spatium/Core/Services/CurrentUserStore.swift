import Combine
import Foundation

/// 로그인한 사용자의 프로필(닉네임/프로필 이미지 등)을 앱 전역에서 공유하기 위한 스토어.
/// 상단 헤더 등 여러 화면이 같은 정보를 구독할 수 있도록 싱글턴으로 둔다.
@MainActor
final class CurrentUserStore: ObservableObject {
    static let shared = CurrentUserStore()

    @Published private(set) var profile: UserProfile?

    private let service = UserService()
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // 로그아웃하면 즉시 비우고, 새로 로그인하면 다시 받아온다.
        // (안 그러면 계정을 바꿔 로그인해도 refreshIfNeeded가 이전 프로필을 재사용한다)
        AuthTokenStore.shared.$isLoggedIn
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] loggedIn in
                guard let self else { return }
                if loggedIn {
                    Task { await self.refresh() }
                } else {
                    self.clear()
                }
            }
            .store(in: &cancellables)
    }

    /// 표시용 닉네임. 없으면 이메일 앞부분으로 폴백.
    var displayName: String? {
        guard let profile else { return nil }
        if !profile.nickname.isEmpty { return profile.nickname }
        return profile.email.split(separator: "@").first.map(String.init)
    }

    /// 프로필 이미지 URL(있을 때만).
    var avatarURL: URL? {
        guard let urlString = profile?.profileImageUrl, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
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
        profile = try? await service.fetchProfile()
    }

    /// 로그아웃 등으로 세션이 사라졌을 때 호출.
    func clear() {
        profile = nil
    }
}
