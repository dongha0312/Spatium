import SwiftUI

/// 첫 실행 시 한 번만 보여주는 기능 소개 온보딩.
/// 실제 앱 화면 스크린샷 4장으로 핵심 흐름(스캔 → 편집 → 가구 생성 → 동기화)을 보여주고,
/// 어느 페이지에서든 "건너뛰기"로 바로 시작할 수 있습니다.
struct OnboardingView: View {
    var onFinished: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            imageName: "OnboardingEditor",
            badgeSystemImage: "camera.viewfinder",
            tintIsSage: false,
            title: "내 방을 3D로 스캔",
            message: "iPhone의 LiDAR 카메라로 방을 비추면\n실제 크기 그대로 3D 공간이 만들어져요."
        ),
        OnboardingPage(
            imageName: "OnboardingCatalog",
            badgeSystemImage: "cube.transparent",
            tintIsSage: true,
            title: "가구를 자유롭게 배치",
            message: "스캔한 방 안에서 가구를 옮기고 돌리고 바꿔보세요.\n구매 전에 크기와 어울림을 미리 확인할 수 있어요."
        ),
        OnboardingPage(
            imageName: "OnboardingImgTo3D",
            badgeSystemImage: "photo.on.rectangle.angled",
            tintIsSage: false,
            title: "사진 한 장이 3D 가구로",
            message: "마음에 드는 가구 사진을 올리면\nAI가 3D 모델로 만들어 방에 놓아볼 수 있어요."
        ),
        OnboardingPage(
            imageName: "OnboardingHome",
            badgeSystemImage: "arrow.triangle.2.circlepath.circle",
            tintIsSage: true,
            title: "웹과 실시간 연동",
            message: "앱에서 스캔한 공간을 웹에서 이어서 편집하세요.\n로그인하면 프로젝트가 기기 간에 동기화됩니다."
        ),
    ]

    private var isLastPage: Bool { currentPage == pages.count - 1 }
    private var usesCompactHeight: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            // 상단: 로고 + 건너뛰기
            HStack {
                BrandMark(size: 34)
                Spacer()
                if !isLastPage {
                    Button("건너뛰기") { onFinished() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SpatiumTheme.soft)
                        .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, usesCompactHeight ? 18 : 24)
            .padding(.top, usesCompactHeight ? 4 : 12)
            .frame(height: usesCompactHeight ? 42 : 56)

            // 가운데: 슬라이드
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page, usesCompactHeight: usesCompactHeight)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: currentPage)

            if usesCompactHeight {
                HStack(spacing: 18) {
                    pageIndicator
                    Spacer(minLength: 8)
                    nextButton
                        .frame(maxWidth: 250)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
            } else {
                pageIndicator
                    .padding(.top, 14)
                    .padding(.bottom, 18)

                nextButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
        .background(SpatiumTheme.background.ignoresSafeArea())
        .accessibilityIdentifier("onboarding-screen")
        .onAppear {
            #if DEBUG
            // 스크린샷 검증용: -UITestOnboardingPage <index>로 특정 슬라이드를 바로 연다.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-UITestOnboardingPage"),
               arguments.indices.contains(index + 1),
               let page = Int(arguments[index + 1]),
               pages.indices.contains(page) {
                currentPage = page
            }
            #endif
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? SpatiumTheme.accent : SpatiumTheme.border)
                    .frame(width: index == currentPage ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("온보딩 \(currentPage + 1) / \(pages.count) 페이지")
    }

    private var nextButton: some View {
        PrimaryButton(
                title: isLastPage ? "Spatium 시작하기" : "다음",
                systemImage: isLastPage ? "arrow.right.circle.fill" : "arrow.right"
            ) {
                if isLastPage {
                    onFinished()
                } else {
                    withAnimation { currentPage += 1 }
                }
            }
    }
}

private struct OnboardingPage {
    let imageName: String
    /// 제목 옆 작은 뱃지 아이콘 — 스크린샷과 함께 기능을 상징한다.
    let badgeSystemImage: String
    /// 포인트 컬러를 sage로 쓸지 accent(브라운)로 쓸지 — 페이지마다 번갈아 준다.
    let tintIsSage: Bool
    let title: String
    let message: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let usesCompactHeight: Bool

    @State private var appeared = false

    private var tint: Color { page.tintIsSage ? SpatiumTheme.sage : SpatiumTheme.accent }

    var body: some View {
        Group {
            if usesCompactHeight {
                HStack(spacing: 24) {
                    screenshot
                        .frame(maxWidth: 360, maxHeight: .infinity)
                    pageDescription
                        .frame(maxWidth: 330)
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 20) {
                    screenshot
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal, 56)
                        .padding(.top, 8)
                    pageDescription
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 4)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }

    private var screenshot: some View {
        Image(page.imageName)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(SpatiumTheme.border, lineWidth: 1)
            )
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(SpatiumTheme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(tint.opacity(0.25), lineWidth: 1.5)
            )
            .shadow(color: SpatiumTheme.shadow.opacity(0.14), radius: 22, y: 12)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .accessibilityLabel("\(page.title) 화면 예시")
    }

    private var pageDescription: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: page.badgeSystemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())

                Text(page.title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
            }

            Text(page.message)
                .font(.footnote)
                .foregroundStyle(SpatiumTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(usesCompactHeight ? 2 : 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .offset(y: appeared ? 0 : 10)
        .opacity(appeared ? 1 : 0)
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
