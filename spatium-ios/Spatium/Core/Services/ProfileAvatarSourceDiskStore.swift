import Foundation

/// 프로필 이미지 원본 문자열을 사용자 ID와 함께 로컬 캐시에 보관합니다.
///
/// 백엔드가 이미지를 큰 data URL로 내려줄 수 있어 Keychain의 최소 사용자 정보에는
/// 포함하지 않고, 앱 재실행 시 서버 응답 전까지만 사용할 디스크 캐시로 분리합니다.
nonisolated final class ProfileAvatarSourceDiskStore: @unchecked Sendable {
    private struct Snapshot: Codable {
        let userID: String
        let source: String
    }

    private let cacheFileURL: URL
    private let operationObserver: (@Sendable (Bool) -> Void)?
    private let queue = DispatchQueue(
        label: "com.spatium.profile-avatar-source-disk-store",
        qos: .utility
    )

    init(
        cacheFileURL: URL? = nil,
        operationObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.cacheFileURL = cacheFileURL ?? Self.defaultCacheFileURL()
        self.operationObserver = operationObserver
    }

    func load(for userID: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                operationObserver?(Thread.isMainThread)
                guard let data = try? Data(contentsOf: cacheFileURL),
                      let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
                      snapshot.userID == userID,
                      !snapshot.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: snapshot.source)
            }
        }
    }

    func save(_ source: String?, for userID: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                operationObserver?(Thread.isMainThread)
                defer { continuation.resume() }

                let normalizedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let normalizedSource, !normalizedSource.isEmpty else {
                    removeSnapshotIfOwned(by: userID)
                    return
                }

                do {
                    try FileManager.default.createDirectory(
                        at: cacheFileURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let snapshot = Snapshot(userID: userID, source: normalizedSource)
                    let data = try JSONEncoder().encode(snapshot)
                    try data.write(to: cacheFileURL, options: .atomic)
                } catch {
                    // 재생성 가능한 표시용 캐시이므로 저장 실패가 프로필 갱신을 막지 않게 한다.
                }
            }
        }
    }

    func clear() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                operationObserver?(Thread.isMainThread)
                try? FileManager.default.removeItem(at: cacheFileURL)
                continuation.resume()
            }
        }
    }

    private func removeSnapshotIfOwned(by userID: String) {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return }

        if let data = try? Data(contentsOf: cacheFileURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
           snapshot.userID != userID {
            return
        }
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    private static func defaultCacheFileURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProfileAvatar", isDirectory: true)
            .appendingPathComponent("current-avatar-source.json", isDirectory: false)
    }
}
