import SwiftUI

struct SettingsView: View {
    @State private var versionTapCount = 0
    @State private var showDeveloperSettings = false

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
                SettingsInfoRow(systemImage: "number", title: "버전", value: appVersion)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: handleVersionTap)
            }
        }
        .sheet(isPresented: $showDeveloperSettings) {
            DeveloperSettingsSheet()
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func handleVersionTap() {
        versionTapCount += 1
        guard versionTapCount >= 5 else { return }
        versionTapCount = 0
        showDeveloperSettings = true
    }
}

private struct AccountSection: View {
    @ObservedObject private var tokenStore = AuthTokenStore.shared
    @State private var profile: UserProfile?
    @State private var showLogin = false
    @State private var showDeleteConfirm = false

    var body: some View {
        SettingsGroup(title: "계정") {
            if tokenStore.isLoggedIn {
                SettingsInfoRow(systemImage: "person.crop.circle", title: "닉네임", value: profile?.nickname ?? "불러오는 중")
                SettingsDivider()
                SettingsInfoRow(systemImage: "envelope", title: "이메일", value: profile?.email ?? "-")
                SettingsDivider()
                DestructiveSettingsButton(systemImage: "rectangle.portrait.and.arrow.right", title: "로그아웃", action: logout)
                SettingsDivider()
                DestructiveSettingsButton(systemImage: "trash", title: "회원 탈퇴") {
                    showDeleteConfirm = true
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
                profile = nil
                return
            }
            profile = try? await UserService().fetchProfile()
        }
        .sheet(isPresented: $showLogin) {
            LoginView(onLoggedIn: {
                showLogin = false
            })
        }
        .sheet(isPresented: $showDeleteConfirm) {
            DeleteAccountSheet(authMethod: tokenStore.authMethod)
        }
    }

    private func logout() {
        Task { try? await AuthService().logout() }
    }
}

/// 스캔/씬 캐시 사용량 표시와 비우기. (다운로드한 방 파일은 다시 받으면 되므로 안전)
private struct StorageSection: View {
    @State private var cacheBytes: Int64 = 0
    @State private var isClearing = false

    private static let cacheDirectoryNames = ["RoomScans", "RoomScenes"]

    var body: some View {
        SettingsGroup(title: "저장 공간") {
            SettingsInfoRow(systemImage: "internaldrive", title: "스캔 캐시", value: Self.format(cacheBytes))
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

private struct DeveloperSettingsSheet: View {
    @ObservedObject private var environment = SpatiumAPIEnvironment.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTestScan: TestRoomData.Scan?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup(title: "연결 (개발자 전용)") {
                    EndpointEditor(baseURLString: $environment.baseURLString)
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

private struct SettingsAppHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image("SpatiumLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))

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

private struct EndpointEditor: View {
    @Binding var baseURLString: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SettingsIcon(systemImage: "server.rack", tint: SpatiumTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("CODEX API 서버")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("다음 요청부터 적용 (호스트만 입력, 경로 제외)")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                }

                Spacer()
            }

            TextField("http://서버IP:8080", text: $baseURLString)
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
