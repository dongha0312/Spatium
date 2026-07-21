import ImageIO
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// 사진 보관함 원본을 전체 해상도로 디코딩하지 않고 아바타 표시·업로드 크기로 바로 줄인다.
enum ProfileAvatarImagePreprocessor {
    nonisolated static let maximumPixelDimension = 512
    nonisolated static let jpegCompressionQuality: CGFloat = 0.85

    struct Prepared: @unchecked Sendable {
        let previewImage: UIImage
        let uploadData: Data
    }

    nonisolated static func prepareInBackground(rawData: Data) async -> Prepared? {
        let worker: Task<Prepared?, Never> = Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard !Task.isCancelled else { return nil }
                return prepare(rawData: rawData)
            }
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated static func prepare(
        rawData: Data,
        maximumPixelDimension: Int = ProfileAvatarImagePreprocessor.maximumPixelDimension
    ) -> Prepared? {
        guard !Task.isCancelled,
              maximumPixelDimension > 0,
              let source = CGImageSourceCreateWithData(rawData as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              !Task.isCancelled else {
            return nil
        }
        // JPEG는 알파를 지원하지 않는다. 알파 채널이 있는 원본(PNG·스크린샷 등)을 그대로 넘기면
        // ImageIO가 "ignoring alpha" 경고와 함께 디코딩 메모리를 2배로 잡으므로,
        // 인코딩 전에 불투명 비트맵으로 한 번 정리한다.
        let encodableImage = makeOpaque(thumbnail)

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegCompressionQuality
        ]
        CGImageDestinationAddImage(destination, encodableImage, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination), !Task.isCancelled else { return nil }

        return Prepared(
            previewImage: UIImage(cgImage: encodableImage),
            uploadData: encoded as Data
        )
    }

    /// 알파 채널이 있는 이미지를 불투명 RGB 비트맵으로 다시 그린다.
    /// 이미 불투명하면 원본을 그대로 돌려주어 불필요한 재그리기를 하지 않는다.
    nonisolated static func makeOpaque(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }
        // 투명 영역이 검게 나오지 않도록 흰 배경 위에 합성한다.
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context.makeImage() ?? image
    }
}

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var profile: UserProfile? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var avatarImage: UIImage? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    /// 백엔드 프로필 API의 projectCount는 하드코딩된 0이라, 프로젝트 API에서 직접 계산해 채운다.
    @State private var projectCount: Int?
    @State private var totalRoomCount: Int?

    private let userService = UserService()

    var body: some View {
        ZStack {
            SpatiumTheme.background.ignoresSafeArea()

            NavigationStack {
                ScrollView {
                    VStack(spacing: 24) {
                        if let profile = profile {
                            // Avatar Section
                            avatarSection

                            // Nickname Input
                            VStack(alignment: .leading, spacing: 8) {
                                Text("닉네임")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(SpatiumTheme.text)

                                TextField("닉네임을 입력하세요", text: $nickname)
                                    .padding(14)
                                    .background(SpatiumTheme.surface)
                                    .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
                            }

                            // Email (Read-only)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("이메일 계정")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(SpatiumTheme.text)

                                HStack {
                                    Text(profile.email)
                                        .font(.subheadline)
                                        .foregroundStyle(SpatiumTheme.soft)
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(SpatiumTheme.muted)
                                }
                                .padding(14)
                                .background(SpatiumTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border.opacity(0.5), lineWidth: 1))
                            }

                            // Stats card
                            statsCard(profile: profile)

                            // Logout Button
                            Button(action: logout) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("로그아웃")
                                }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(SpatiumTheme.coral)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(SpatiumTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.coral.opacity(0.2), lineWidth: 1.2))
                                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
                            }
                            .buttonStyle(.pressable)
                            .padding(.top, 8)
                        } else {
                            ProgressView("프로필 정보를 불러오는 중...")
                                .padding(.top, 40)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(SpatiumTheme.background.ignoresSafeArea())
                .navigationTitle("프로필 설정")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") { saveProfile() }
                            .font(.headline.weight(.bold))
                            .disabled(isLoading || nickname.isEmpty)
                    }
                }
                .task {
                    await loadProfile()
                    await loadStats()
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    if let newItem {
                        loadSelectedPhoto(newItem)
                    }
                }
            }
        }
        .accessibilityIdentifier("profile-edit-full-screen")
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                if let avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 86, height: 86)
                        .clipShape(Circle())
                } else {
                    ProfileImageView(source: profile?.profileImageUrl) {
                        Circle()
                            .fill(SpatiumTheme.warmPanel)
                            .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(SpatiumTheme.accentLight)
                        }
                    }
                    .frame(width: 86, height: 86)
                    .clipShape(Circle())
                }
            }
            // 사진 보관함 원본을 읽어 줄이고 업로드하는 동안 아바타 자리에 진행 표시를 둔다.
            // (없으면 큰 원본에서 몇 초간 아무 반응이 없는 것처럼 보인다)
            .overlay {
                if isLoading {
                    ZStack {
                        Circle().fill(.black.opacity(0.4))
                        ProgressView()
                            .tint(.white)
                    }
                    .frame(width: 86, height: 86)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isLoading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isLoading ? "프로필 사진 변경 중" : "프로필 사진")
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(SpatiumTheme.accent)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
            }
            
            if profile?.profileImageUrl != nil || avatarImage != nil {
                Button("사진 삭제") {
                    deleteAvatar()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.coral)
                .padding(.top, 2)
            }
        }
    }

    private func statsCard(profile: UserProfile) -> some View {
        Card {
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("보관 중인 프로젝트")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                    Text(projectCount.map { "\($0)개" } ?? "-")
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(SpatiumTheme.border)
                    .frame(width: 1, height: 32)

                VStack(spacing: 6) {
                    Text("총 룸 개수")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                    Text(totalRoomCount.map { "\($0)개" } ?? "-")
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        }
    }

    /// 프로젝트 목록/방 목록 API에서 실제 개수를 계산한다.
    /// (프로필 API의 projectCount·placedFurnitureCount는 서버에서 0으로 고정돼 있어 쓰지 않는다)
    private func loadStats() async {
        guard let projects = try? await ProjectService().fetchProjects() else { return }
        projectCount = projects.count

        var total = 0
        await withTaskGroup(of: Int.self) { group in
            for project in projects {
                let projectID = project.id
                let fallbackCount = project.displayRoomCount
                group.addTask {
                    (try? await ProjectService().fetchRoomCount(projectID: projectID)) ?? fallbackCount
                }
            }
            for await count in group {
                total += count
            }
        }
        totalRoomCount = total
    }

    private func loadProfile() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestProfileSheet") {
            let fixture = UserProfile(
                userId: "ui-test-user",
                email: "ui-test@spatium.com",
                nickname: "UI 테스트 사용자",
                birthDate: nil,
                gender: nil,
                profileImageUrl: nil,
                projectCount: 1,
                placedFurnitureCount: 0
            )
            profile = fixture
            nickname = fixture.nickname
            projectCount = 1
            totalRoomCount = 0
            return
        }
        #endif

        do {
            let loaded = try await userService.fetchProfile()
            profile = loaded
            nickname = loaded.nickname
        } catch {
            errorMessage = "프로필을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem) {
        isLoading = true
        errorMessage = nil
        
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let prepared = await ProfileAvatarImagePreprocessor.prepareInBackground(rawData: data) else {
                errorMessage = "선택한 프로필 사진을 처리하지 못했습니다."
                isLoading = false
                return
            }
            avatarImage = prepared.previewImage

            // Upload to server immediately
            do {
                let result = try await userService.uploadAvatar(imageData: prepared.uploadData)
                profile?.profileImageUrl = result.profileImageUrl
            } catch {
                errorMessage = "프로필 사진 업로드 실패: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func deleteAvatar() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await userService.deleteAvatar()
                avatarImage = nil
                profile?.profileImageUrl = nil
            } catch {
                errorMessage = "사진 삭제 실패: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func saveProfile() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let req = UserUpdateRequest(nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines))
                _ = try await userService.updateProfile(req)
                isLoading = false
                dismiss()
            } catch {
                isLoading = false
                errorMessage = "저장 실패: \(error.localizedDescription)"
            }
        }
    }

    private func logout() {
        // 로컬 로그아웃은 즉시 완료된다(서버 세션 무효화는 배경에서 진행).
        AuthService().logout()
        dismiss()
    }
}
