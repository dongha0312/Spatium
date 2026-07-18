import SwiftUI

/// RoomPlan은 여러 방을 한 세션에 이어 담으면 벽 경계와 가구 분류가 불안정해질 수 있다.
/// 실제 카메라를 열기 전에 방 하나 단위의 스캔 원칙을 반드시 확인하게 한다.
struct ScanPreparationSheet: View {
    var onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesLargeDetent: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SpatiumSpacing.md) {
                    header
                    reasonCard
                    checklist
                }
                .padding(.horizontal, SpatiumSpacing.lg)
                .padding(.top, SpatiumSpacing.md)
                .padding(.bottom, SpatiumSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("scan-one-room-guidance")

            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SpatiumTheme.background.ignoresSafeArea())
        .presentationDetents(usesLargeDetent ? [.large] : [.height(520)])
        .presentationDragIndicator(.visible)
        .presentationBackground(SpatiumTheme.background)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "viewfinder.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(SpatiumTheme.onCta)
                .frame(width: 48, height: 48)
                .background(SpatiumTheme.ctaFill, in: RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("한 방 = 스캔 1회")
                    .font(.caption.weight(.black))
                    .foregroundStyle(SpatiumTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(SpatiumTheme.accent.opacity(0.10), in: Capsule())

                Text("한 번에 방 하나만 스캔해 주세요")
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.black))
                    .foregroundStyle(SpatiumTheme.muted)
                    .frame(width: 36, height: 36)
                    .background(SpatiumTheme.warmPanel, in: Circle())
                    .overlay(Circle().stroke(SpatiumTheme.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("스캔 안내 닫기")
            .accessibilityIdentifier("scan-preparation-close-button")
        }
    }

    private var reasonCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
                .accessibilityHidden(true)

            Text("여러 방을 이어 담으면 벽 경계와 가구 위치·카테고리 인식이 부정확해질 수 있어요.")
                .font(.footnote.weight(.medium))
                .lineSpacing(3)
                .foregroundStyle(SpatiumTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpatiumTheme.warmPanel)
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                .stroke(SpatiumTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("이렇게 스캔하세요")
                .font(.subheadline.weight(.black))
                .foregroundStyle(SpatiumTheme.text)

            VStack(spacing: 0) {
                ScanPreparationRule(
                    number: 1,
                    title: "현재 방 안에서만 이동하기",
                    detail: "출입문 너머의 다른 방까지 이어서 스캔하지 마세요."
                )

                ruleDivider

                ScanPreparationRule(
                    number: 2,
                    title: "벽과 가구를 천천히 비추기",
                    detail: "방을 한 바퀴 돌며 벽·바닥·가구를 충분히 보여 주세요."
                )

                ruleDivider

                ScanPreparationRule(
                    number: 3,
                    title: "다른 방은 새 스캔으로 시작하기",
                    detail: "현재 방을 완료한 뒤 다음 방에서 새 스캔을 시작하세요."
                )
            }
            .padding(.horizontal, 14)
            .background(SpatiumTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                    .stroke(SpatiumTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
    }

    private var ruleDivider: some View {
        Divider()
            .overlay(SpatiumTheme.border)
            .padding(.leading, 44)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(SpatiumTheme.border)

            Button {
                Haptics.selection()
                onStart()
                dismiss()
            } label: {
                Label("이 방 스캔 시작", systemImage: "camera.viewfinder")
                    .font(.headline.weight(.black))
                    .foregroundStyle(SpatiumTheme.onCta)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(SpatiumTheme.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                    .shadow(color: SpatiumTheme.shadow.opacity(0.14), radius: 10, y: 5)
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("scan-preparation-start-button")
            .padding(.horizontal, SpatiumSpacing.lg)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }
}

private struct ScanPreparationRule: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number.formatted())
                .font(.caption.weight(.black))
                .foregroundStyle(SpatiumTheme.onCta)
                .frame(width: 32, height: 32)
                .background(SpatiumTheme.ctaFill, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SpatiumTheme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number)단계. \(title). \(detail)")
    }
}
