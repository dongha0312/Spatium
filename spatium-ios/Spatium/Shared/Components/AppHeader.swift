import SwiftUI

struct AppHeader: View {
    let selectedTab: AppTab
    @ObservedObject private var tokenStore = AuthTokenStore.shared
    @ObservedObject private var currentUser = CurrentUserStore.shared

    @State private var showLoginSheet = false
    @State private var showProfileSheet = false

    var body: some View {
        HStack(spacing: 12) {
            BrandMark(size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab == .home ? "SPATIUM" : selectedTab.title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Text(selectedTab == .home ? "3D 공간 인테리어" : "SPATIUM · 3D 인테리어")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()

            // Login Status Badge on the top right
            loginStatusBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(SpatiumTheme.chromeSurface)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SpatiumTheme.border.opacity(0.7))
                .frame(height: 0.5)
        }
        .animation(.default, value: selectedTab)
        .task { await currentUser.refreshIfNeeded() }
        .onChange(of: tokenStore.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                Task { await currentUser.refresh() }
            } else {
                currentUser.clear()
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(onLoggedIn: {})
        }
        .sheet(isPresented: $showProfileSheet, onDismiss: {
            // 프로필 수정(닉네임/이미지) 후 헤더도 최신 상태로 갱신.
            Task { await currentUser.refresh() }
        }) {
            ProfileEditView()
        }
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
        Group {
            if let url = currentUser.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
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
