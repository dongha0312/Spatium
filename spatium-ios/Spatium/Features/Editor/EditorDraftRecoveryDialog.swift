import SwiftUI

/// 에디터 진입 시 발견한 로컬 임시 저장본을 복구하거나 폐기하는 중앙 카드 팝업.
/// 시스템 하단 시트와 분리해 홈 인디케이터가 있는 실기기에서도 카드 전체가 화면 안에 표시된다.
struct EditorDraftRecoveryDialog: View {
    let savedAt: Date?
    var onRestore: () -> Void
    var onDiscard: () async -> Void

    @State private var isDiscarding = false

    private var savedAtText: String {
        guard let savedAt else { return "최근 자동 저장본" }
        return savedAt.formatted(.dateTime.month().day().hour().minute())
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                ScrollView {
                    dialogCard
                        .frame(maxWidth: 420)
                        .padding(.horizontal, SpatiumSpacing.lg)
                        .padding(.vertical, SpatiumSpacing.xl)
                        .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("editor-draft-recovery-dialog")
    }

    private var dialogCard: some View {
        VStack(spacing: SpatiumSpacing.md) {
            header
            recoveryCard
            actions
        }
        .padding(SpatiumSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            SpatiumTheme.background,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(SpatiumTheme.border.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: SpatiumTheme.shadow.opacity(0.22), radius: 28, y: 14)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2.weight(.bold))
                .foregroundStyle(SpatiumTheme.onCta)
                .frame(width: 58, height: 58)
                .background(SpatiumTheme.ctaFill, in: Circle())
                .shadow(color: SpatiumTheme.shadow.opacity(0.12), radius: 8, y: 4)
                .accessibilityHidden(true)

            Text("임시 저장본 발견")
                .font(.caption.weight(.black))
                .foregroundStyle(SpatiumTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(SpatiumTheme.accent.opacity(0.10), in: Capsule())

            Text("이어서 편집할까요?")
                .font(.title3.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("마지막 편집 상태")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                    Text(savedAtText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SpatiumTheme.soft)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(SpatiumTheme.success)
            }

            Divider()
                .overlay(SpatiumTheme.border)

            Text("가구 배치와 편집 내용이 이 기기에 자동 저장되어 있어요. 복구하면 저장 당시 상태부터 계속할 수 있습니다.")
                .font(.footnote.weight(.medium))
                .lineSpacing(3)
                .foregroundStyle(SpatiumTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Label("새로 시작하면 이 임시 저장본은 삭제돼요.", systemImage: "info.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SpatiumTheme.coral)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpatiumTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous)
                .stroke(SpatiumTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                discardButton
                restoreButton
            }

            VStack(spacing: 10) {
                restoreButton
                discardButton
            }
        }
    }

    private var discardButton: some View {
        Button {
            guard !isDiscarding else { return }
            isDiscarding = true
            Task {
                await onDiscard()
            }
        } label: {
            Group {
                if isDiscarding {
                    ProgressView()
                        .tint(SpatiumTheme.coral)
                } else {
                    Text("새로 시작")
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(SpatiumTheme.coral)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(SpatiumTheme.warmPanel)
            .overlay(Capsule().stroke(SpatiumTheme.border, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.pressable)
        .contentShape(Capsule())
        .disabled(isDiscarding)
        .accessibilityHint("기기에 저장된 임시 편집 내용을 삭제합니다.")
        .accessibilityIdentifier("editor-draft-discard-button")
    }

    private var restoreButton: some View {
        Button {
            guard !isDiscarding else { return }
            onRestore()
        } label: {
            Label("이어서 편집", systemImage: "arrow.forward")
                .font(.subheadline.weight(.black))
                .foregroundStyle(SpatiumTheme.onCta)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(SpatiumTheme.ctaFill)
                .clipShape(Capsule())
                .shadow(color: SpatiumTheme.shadow.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(.pressable)
        .contentShape(Capsule())
        .disabled(isDiscarding)
        .accessibilityHint("마지막 자동 저장 상태를 불러옵니다.")
        .accessibilityIdentifier("editor-draft-restore-button")
    }
}
