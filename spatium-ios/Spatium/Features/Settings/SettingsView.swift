import SwiftUI

struct SettingsView: View {
    #if DEBUG
    @State private var versionTapCount = 0
    @State private var showDeveloperSettings = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsAppHeader()

            AccountSection()

            StorageSection()

            SettingsGroup(title: "법적 정보") {
                LegalLinkRow(systemImage: "hand.raised", title: "개인정보처리방침", url: SpatiumLegalLinks.privacyPolicyURL)
                SettingsDivider()
                LegalLinkRow(systemImage: "doc.text", title: "이용약관", url: SpatiumLegalLinks.termsOfServiceURL)
            }

            SupportSection()

            SettingsGroup(title: "앱") {
                #if DEBUG
                SettingsInfoRow(systemImage: "number", title: "버전", value: appVersion)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: handleVersionTap)
                #else
                SettingsInfoRow(systemImage: "number", title: "버전", value: appVersion)
                #endif
            }
        }
        #if DEBUG
        .sheet(isPresented: $showDeveloperSettings) {
            DeveloperSettingsSheet()
        }
        #endif
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    #if DEBUG
    private func handleVersionTap() {
        versionTapCount += 1
        guard versionTapCount >= 5 else { return }
        versionTapCount = 0
        showDeveloperSettings = true
    }
    #endif
}

private struct AccountSection: View {
    @ObservedObject private var tokenStore = AuthTokenStore.shared
    @ObservedObject private var currentUser = CurrentUserStore.shared
    @State private var showLogin = false
    @State private var showDeleteConfirm = false
    @State private var accountActionError: String?

    var body: some View {
        SettingsGroup(title: "계정") {
            if tokenStore.isLoggedIn {
                SettingsInfoRow(systemImage: "person.crop.circle", title: "닉네임", value: currentUser.profile?.nickname ?? "불러오는 중")
                SettingsDivider()
                SettingsInfoRow(systemImage: "envelope", title: "이메일", value: currentUser.profile?.email ?? "-")
                SettingsDivider()
                DestructiveSettingsButton(systemImage: "rectangle.portrait.and.arrow.right", title: "로그아웃", action: logout)
                SettingsDivider()
                DestructiveSettingsButton(systemImage: "trash", title: "회원 탈퇴") {
                    showDeleteConfirm = true
                }
                if let accountActionError {
                    Text(accountActionError)
                        .font(.caption2)
                        .foregroundStyle(SpatiumTheme.coral)
                        .padding(.top, 2)
                }
            } else {
                Button {
                    showLogin = true
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(systemImage: "person.crop.circle.badge.plus", tint: SpatiumTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("로그인")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(SpatiumTheme.text)
                            Text("로그인하면 프로젝트가 기기 간에 동기화됩니다")
                                .font(.caption)
                                .foregroundStyle(SpatiumTheme.soft)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SpatiumTheme.soft)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
            }
        }
        .task(id: tokenStore.isLoggedIn) {
            guard tokenStore.isLoggedIn else {
                return
            }
            await currentUser.refreshIfNeeded()
        }
        .sheet(isPresented: $showLogin) {
            LoginView(onLoggedIn: {
                showLogin = false
            })
        }
        .sheet(isPresented: $showDeleteConfirm) {
            ConfirmSheet(
                title: "정말 탈퇴하시겠어요?",
                message: "모든 프로젝트와 데이터가 삭제되며 되돌릴 수 없습니다.",
                confirmTitle: "탈퇴하기",
                onConfirm: deleteAccount
            )
        }
    }

    private func logout() {
        // 로컬 로그아웃은 즉시 완료된다(서버 세션 무효화는 배경에서 진행).
        AuthService().logout()
    }

    private func deleteAccount() {
        accountActionError = nil
        Task {
            do {
                if AuthTokenStore.shared.accessToken?.hasPrefix("mock_") == true {
                    // mock 세션(시뮬레이터 로그인)은 서버에 계정이 없으므로 로컬만 정리한다.
                    AuthTokenStore.shared.clear()
                } else {
                    try await UserService().deleteAccount()
                }
            } catch {
                // 실패를 삼키면 사용자는 탈퇴된 줄 알게 되므로 반드시 표시한다.
                accountActionError = "탈퇴하지 못했어요: \(error.localizedDescription)"
            }
        }
    }
}

/// 스캔/씬/생성 모델 캐시 사용량 표시와 비우기.
/// (다운로드한 방 파일은 다시 받으면 되고, 저장 완료된 내 가구 GLB는
///  Application Support에 있어 영향을 받지 않는다)
private struct StorageSection: View {
    @State private var cacheBytes: Int64 = 0
    @State private var isClearing = false

    /// "Spatium"은 가구 만들기의 GeneratedModels/CorrectedModels 중간 산출물 폴더.
    private static let cacheDirectoryNames = ["RoomScans", "RoomScenes", "Spatium"]

    var body: some View {
        SettingsGroup(title: "저장 공간") {
            SettingsInfoRow(systemImage: "internaldrive", title: "스캔·모델 캐시", value: Self.format(cacheBytes))
            SettingsDivider()
            Button(action: clearCache) {
                HStack(spacing: 12) {
                    SettingsIcon(systemImage: "arrow.triangle.2.circlepath", tint: SpatiumTheme.accent)
                    Text(isClearing ? "비우는 중..." : "캐시 비우기")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(cacheBytes > 0 ? SpatiumTheme.accent : SpatiumTheme.soft)
                    Spacer()
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.pressable)
            .disabled(isClearing || cacheBytes == 0)
        }
        .task { cacheBytes = Self.totalBytes() }
    }

    private func clearCache() {
        isClearing = true
        Task {
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            for name in Self.cacheDirectoryNames {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
            }
            cacheBytes = Self.totalBytes()
            isClearing = false
            Haptics.success()
        }
    }

    private static func totalBytes() -> Int64 {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        var total: Int64 = 0
        for name in cacheDirectoryNames {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let file as URL in files {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    private static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "없음" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// 문의 메일과 오픈소스 라이선스 고지.
private struct SupportSection: View {
    @State private var showLicenses = false

    var body: some View {
        SettingsGroup(title: "지원") {
            LegalLinkRow(systemImage: "envelope", title: "문의하기", url: URL(string: "mailto:rsj1001@gmail.com")!)
            SettingsDivider()
            Button {
                showLicenses = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon(systemImage: "shippingbox", tint: SpatiumTheme.muted)
                    Text("오픈소스 라이선스")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.soft)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.pressable)
        }
        .sheet(isPresented: $showLicenses) {
            OpenSourceLicensesSheet()
        }
    }
}

private struct OpenSourceLicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("GLTFKit2")
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("Copyright (c) Warren Moore\nMIT License")
                        .font(.footnote)
                        .foregroundStyle(SpatiumTheme.muted)
                    Text("""
                    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

                    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.
                    """)
                        .font(.caption2)
                        .foregroundStyle(SpatiumTheme.soft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("오픈소스 라이선스")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}

private struct DestructiveSettingsButton: View {
    let systemImage: String
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsIcon(systemImage: systemImage, tint: SpatiumTheme.coral)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.coral)
                Spacer()
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.pressable)
    }
}

#if DEBUG
private struct DeveloperSettingsSheet: View {
    @ObservedObject private var environment = SpatiumAPIEnvironment.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTestScan: TestRoomData.Scan?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup(title: "연결 (개발자 전용)") {
                    EndpointEditor(
                        springBaseURLString: $environment.baseURLString,
                        furnitureAssetBaseURLString: $environment.furnitureAssetBaseURLString
                    )
                }

                #if DEBUG
                SettingsGroup(title: "테스트") {
                    ForEach(TestRoomData.scans) { scan in
                        Button {
                            selectedTestScan = scan
                        } label: {
                            HStack(spacing: 12) {
                                SettingsIcon(systemImage: "cube.transparent", tint: SpatiumTheme.accent)
                                Text(scan.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(SpatiumTheme.text)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(SpatiumTheme.soft)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)

                        if scan.id != TestRoomData.scans.last?.id {
                            SettingsDivider()
                        }
                    }
                }
                #endif

                Spacer()
            }
            .padding(20)
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("개발자 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            #if DEBUG
            .fullScreenCover(item: $selectedTestScan) { scan in
                if let test = scan.load() {
                    RoomEditorView(
                        scanItems: test.items,
                        roomName: scan.roomName,
                        usdzURL: test.usdzURL,
                        area: scan.area,
                        ceilingHeight: scan.ceilingHeight
                    )
                } else {
                    Text("테스트 스캔을 불러오지 못했습니다.")
                }
            }
            #endif
        }
    }
}
#endif

private struct SettingsAppHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            BrandMark(size: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("Spatium")
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Text("공간 스캔 및 3D 업로드")
                    .font(.subheadline)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(SpatiumTheme.soft)
                .padding(.horizontal, 4)

            Card {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

#if DEBUG
private struct EndpointEditor: View {
    @Binding var springBaseURLString: String
    @Binding var furnitureAssetBaseURLString: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SettingsIcon(systemImage: "server.rack", tint: SpatiumTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Spring Boot API 서버")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("다음 요청부터 적용 (호스트만 입력, 경로 제외)")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                }

                Spacer()
            }

            TextField("http://서버IP:8080", text: $springBaseURLString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .padding(12)
                .background(SpatiumTheme.background)
                .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))

            HStack(spacing: 12) {
                SettingsIcon(systemImage: "shippingbox", tint: SpatiumTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("기본 가구 에셋 서버")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("기본 카탈로그의 공개 /data 모델 경로에 사용")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                }
                Spacer()
            }

            TextField("http://서버IP:3000", text: $furnitureAssetBaseURLString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .padding(12)
                .background(SpatiumTheme.background)
                .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
    }
}
#endif

private struct LegalLinkRow: View {
    let systemImage: String
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                SettingsIcon(systemImage: systemImage, tint: SpatiumTheme.muted)

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.soft)
            }
            .frame(minHeight: 44)
        }
    }
}

private struct SettingsInfoRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: SpatiumTheme.sky)

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.text)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(SpatiumTheme.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(minHeight: 44)
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SpatiumTheme.border)
            .frame(height: 1)
            .padding(.leading, 44)
            .padding(.vertical, 8)
    }
}
