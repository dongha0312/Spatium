import SwiftUI
import PhotosUI
import UIKit

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

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                if let avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 86, height: 86)
                        .clipShape(Circle())
                } else if let urlString = profile?.profileImageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 86, height: 86)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(SpatiumTheme.warmPanel)
                        .frame(width: 86, height: 86)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(SpatiumTheme.accentLight)
                        }
                }
            }
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
                group.addTask {
                    (try? await ProjectService().fetchRoomCount(projectID: project.id)) ?? project.displayRoomCount
                }
            }
            for await count in group {
                total += count
            }
        }
        totalRoomCount = total
    }

    private func loadProfile() async {
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
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                avatarImage = uiImage

                // Upload to server immediately
                do {
                    // 원본은 수 MB HEIC일 수 있으므로 서버 명세(JPEG)에 맞게 줄여 인코딩해 올린다.
                    let jpegData = Self.avatarUploadData(from: uiImage)
                    let result = try await userService.uploadAvatar(imageData: jpegData)
                    profile?.profileImageUrl = result.profileImageUrl
                } catch {
                    errorMessage = "프로필 사진 업로드 실패: \(error.localizedDescription)"
                }
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

    /// 아바타 업로드용 데이터: 최대 512px로 줄이고 JPEG로 인코딩.
    private static func avatarUploadData(from image: UIImage) -> Data {
        let maxDimension: CGFloat = 512
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.85) ?? Data()
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
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await AuthService().logout()
                isLoading = false
                dismiss()
            } catch {
                isLoading = false
                errorMessage = "로그아웃 실패: \(error.localizedDescription)"
            }
        }
    }
}
