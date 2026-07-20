import SwiftUI

struct AppHeader: View {
    let selectedTab: AppTab
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject private var tokenStore = AuthTokenStore.shared
    @ObservedObject private var currentUser = CurrentUserStore.shared

    @State private var showLoginSheet = false
    @State private var showProfileSheet = false

    private var usesCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        HStack(spacing: usesCompactHeight ? 9 : 12) {
            BrandMark(size: usesCompactHeight ? 21 : 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab == .home ? "SPATIUM" : selectedTab.title)
                    .font((usesCompactHeight ? Font.headline : Font.title3).weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                if !usesCompactHeight {
                    Text(selectedTab == .home ? "3D 공간 인테리어" : "SPATIUM · 3D 인테리어")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(SpatiumTheme.soft)
                }
            }

            Spacer()

            // Login Status Badge on the top right
            loginStatusBadge
        }
        .padding(.horizontal, usesCompactHeight ? 14 : 20)
        .padding(.vertical, usesCompactHeight ? 6 : 12)
        .frame(maxWidth: .infinity)
        .background(SpatiumTheme.chromeSurface)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SpatiumTheme.border.opacity(0.7))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-header")
        .animation(.default, value: selectedTab)
        .task { await currentUser.refreshIfNeeded() }
        .onChange(of: tokenStore.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                Task { await currentUser.refresh() }
            } else {
                currentUser.clear()
            }
        }
        .fullScreenCover(isPresented: $showLoginSheet) {
            LoginView(onLoggedIn: {})
        }
        .fullScreenCover(isPresented: $showProfileSheet, onDismiss: {
            // 프로필 수정(닉네임/이미지) 후 헤더도 최신 상태로 갱신.
            Task { await currentUser.refresh() }
        }) {
            ProfileEditView()
        }
        #if DEBUG
        .onAppear {
            guard ProcessInfo.processInfo.arguments.contains("-UITestProfileSheet") else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                showProfileSheet = true
            }
        }
        #endif
    }

    @ViewBuilder
    private var loginStatusBadge: some View {
        Button {
            if tokenStore.isLoggedIn {
                showProfileSheet = true
            } else {
                showLoginSheet = true
            }
        } label: {
            if tokenStore.isLoggedIn {
                profileBadge
            } else {
                guestBadge
            }
        }
        .buttonStyle(.pressable)
    }

    private var profileBadge: some View {
        HStack(spacing: 7) {
            avatar
            Text(currentUser.displayName ?? "회원")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SpatiumTheme.text)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 11)
        .padding(.vertical, 4)
        .background(SpatiumTheme.elevatedSurface)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(SpatiumTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private var avatar: some View {
        ProfileImageView(source: currentUser.avatarSource) {
            avatarPlaceholder
        }
        .frame(width: 26, height: 26)
        .clipShape(Circle())
        .overlay(Circle().stroke(SpatiumTheme.border, lineWidth: 1))
    }

    private var avatarPlaceholder: some View {
        ZStack {
            SpatiumTheme.accent.opacity(0.14)
            Image(systemName: "person.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SpatiumTheme.accent)
        }
    }

    private var guestBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.crop.circle")
                .font(.footnote)
            Text("게스트")
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SpatiumTheme.elevatedSurface)
        .foregroundStyle(SpatiumTheme.muted)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(SpatiumTheme.border.opacity(0.8), lineWidth: 1)
        )
    }
}
