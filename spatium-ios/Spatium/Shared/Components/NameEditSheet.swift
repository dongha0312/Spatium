import SwiftUI

/// 이름 수정 팝업 — 시스템 alert 대신 앱 톤(테마 배경 + PrimaryButton)으로 통일한 하단 시트.
/// 프로젝트/방 이름 수정 등 한 줄 텍스트 입력에 공용으로 사용합니다.
struct NameEditSheet: View {
    let title: String
    let hint: String
    let placeholder: String
    let confirmTitle: String
    var onSave: (String) -> Void

    @State private var name: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        hint: String,
        placeholder: String,
        initialName: String,
        confirmTitle: String = "저장하기",
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.hint = hint
        self.placeholder = placeholder
        self.confirmTitle = confirmTitle
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var needsExpandedSheet: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline.weight(.black))
                            .foregroundStyle(SpatiumTheme.text)
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(SpatiumTheme.soft)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SpatiumTheme.soft)
                            .frame(width: 30, height: 30)
                            .background(SpatiumTheme.warmPanel, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("닫기")
                }

                TextField(placeholder, text: $name)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .padding(12)
                    .background(SpatiumTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
                    .onSubmit(save)

                PrimaryButton(title: confirmTitle, systemImage: "checkmark", action: save)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SpatiumTheme.background.ignoresSafeArea())
        .presentationDetents(needsExpandedSheet ? [.large] : [.height(210)])
        .presentationDragIndicator(.visible)
        .presentationBackground(SpatiumTheme.background)
        .onAppear { isFocused = true }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
        dismiss()
    }
}
