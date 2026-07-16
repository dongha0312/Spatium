import SwiftUI

/// 서버 저장 버튼과 로컬 임시 저장 상태를 표시하는 에디터 하단 액션 바.
struct EditorFooterView: View {
    let hasUnsavedChanges: Bool
    let draftSaveState: EditorDraftSaveState
    let isGuestLocalProject: Bool
    let isOffline: Bool
    let isSaving: Bool
    let onDiscard: () -> Void
    let onSave: () -> Void
    let onRetryDraftSave: () -> Void

    private var isSaveUnavailable: Bool {
        isOffline || isGuestLocalProject
    }

    var body: some View {
        VStack(spacing: 8) {
            if hasUnsavedChanges, let failureMessage = draftSaveState.failureMessage {
                draftSaveFailureRow(message: failureMessage)
            }

            HStack(spacing: 8) {
                footerStatus
                Spacer()
                discardButton
                saveButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    SpatiumTheme.editorToolbar.opacity(0.96),
                    SpatiumTheme.editorPanel
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: -5)
        .accessibilityIdentifier("editor-footer")
    }

    @ViewBuilder
    private var footerStatus: some View {
        if hasUnsavedChanges {
            switch draftSaveState {
            case .idle, .saving:
                Label("이 기기에 임시 저장 중...", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            case .saved:
                Label("이 기기에 임시 저장됨", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            case .failed:
                EmptyView()
            }
        } else if isGuestLocalProject {
            Text("게스트 프로젝트 — 로그인하면 서버에 저장할 수 있어요")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        } else if isOffline {
            Text("편집 내용이 서버에 저장되지 않아요 — 이 기기에만 보관돼요")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
    }

    private var discardButton: some View {
        Button(action: onDiscard) {
            Text("취소하기")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.pressable)
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("저장하기").font(.caption.weight(.black))
                }
            }
            .foregroundStyle(.white.opacity(isSaveUnavailable ? 0.5 : 1))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(SpatiumTheme.accent.opacity(isSaveUnavailable ? 0.45 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(isSaving || isSaveUnavailable)
    }

    private func draftSaveFailureRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.coral)

            VStack(alignment: .leading, spacing: 1) {
                Text("임시 저장 실패")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button("다시 시도", action: retryDraftSave)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(SpatiumTheme.coral, in: Capsule())
                .buttonStyle(.pressable)
                .accessibilityLabel("임시 저장 다시 시도")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            SpatiumTheme.coral.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SpatiumTheme.coral.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor-draft-save-failure")
    }

    private func retryDraftSave() {
        Haptics.selection()
        onRetryDraftSave()
    }
}
