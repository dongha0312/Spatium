import SwiftUI

struct NewProjectSheet: View {
    @State private var name = ""
    @State private var isCreating = false
    @State private var showAction = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    var onCreate: (String) async -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("프로젝트 이름")
                    .font(.headline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)

                Text("예: 우리집, 신혼집 인테리어, 사무실 리모델링")
                    .font(.footnote)
                    .foregroundStyle(SpatiumTheme.soft)

                TextField("프로젝트 이름을 입력하세요", text: $name)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .padding(14)
                    .background(SpatiumTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
                    .onSubmit(createProject)

                Spacer()

                NewProjectCreateButton(action: createProject)
                    .disabled(isCreating)
                    .opacity(showAction ? 1 : 0)
            }
            .padding(20)
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("새 프로젝트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(isCreating)
                }
            }
            .task {
                await Task.yield()
                isFocused = true
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.easeOut(duration: 0.16)) {
                    showAction = true
                }
            }
        }
    }

    private func createProject() {
        guard !isCreating else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreating = true
        Task {
            await onCreate(trimmed)
            isCreating = false
            dismiss()
        }
    }
}

private struct NewProjectCreateButton: View {
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SpatiumTheme.accentLight, SpatiumTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                HStack(spacing: 8) {
                    Image(systemName: "arrow.right")
                    Text("프로젝트 만들고 스캔 시작")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .frame(height: 54)
            .opacity(isEnabled ? 1 : 0.45)
            .saturation(isEnabled ? 1 : 0.6)
            .compositingGroup()
        }
        .buttonStyle(.pressable)
        .contentShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }
}
