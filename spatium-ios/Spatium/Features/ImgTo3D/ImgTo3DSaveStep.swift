import SwiftUI

struct ImgTo3DSaveStep: View {
    @Binding var saveName: String
    @Binding var category: ImgTo3DCategory
    let focusedField: FocusState<ImgTo3DFocusField?>.Binding
    let saved: Bool
    let isSaving: Bool
    let saveNotice: String?
    let importedModelName: String?
    let modelFileSizeText: String
    let normalizedEnglishName: String?
    let onSave: () -> Void
    let onReset: () -> Void

    var body: some View {
        Group {
            if saved {
                successContent
            } else {
                saveForm
            }
        }
    }

    private var successContent: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(SpatiumTheme.success)
                .frame(width: 88, height: 88)
                .background(SpatiumTheme.success.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(SpatiumTheme.success.opacity(0.2), lineWidth: 1))
                .symbolEffect(.bounce, value: saved)
            Text("가구 목록에 추가했어요!")
                .font(.title2.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
            Text(saveNotice ?? "이제 3D 에디터에서 “\(saveName)”을(를) 방에 배치할 수 있어요.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(saveNotice == nil ? SpatiumTheme.soft : SpatiumTheme.accent)
            Spacer(minLength: 0)
            PrimaryButton(
                title: "새 모델 만들기",
                systemImage: "plus.square.on.square",
                action: onReset
            )
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var saveForm: some View {
        ImgTo3DStepShell(
            systemImage: "square.and.arrow.down.fill",
            title: "마지막으로 확인해주세요",
            description: "저장하면 내 가구 목록에서 바로 사용할 수 있어요."
        ) {
            VStack(spacing: 15) {
                nameField
                categoryPicker
                generatedFileSummary
                Text("저장한 모델은 프로젝트의 내 가구와 3D 에디터 카탈로그에서 바로 사용할 수 있어요.")
                    .font(.caption)
                    .lineSpacing(3)
                    .foregroundStyle(SpatiumTheme.soft)
                PrimaryButton(
                    title: isSaving ? "저장 중…" : "가구 목록에 추가",
                    systemImage: "plus.circle.fill",
                    action: onSave
                )
                .disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("가구 이름").font(.subheadline.weight(.bold))
            TextField("가구 이름", text: $saveName)
                .focused(focusedField, equals: .saveName)
                .padding(13)
                .background(SpatiumTheme.elevatedSurface)
                .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("카테고리").font(.subheadline.weight(.bold))
            Picker("카테고리", selection: $category) {
                ForEach(ImgTo3DCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(SpatiumTheme.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generatedFileSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("생성된 파일")
                .font(.caption.weight(.black))
                .foregroundStyle(SpatiumTheme.soft)
            Text(importedModelName ?? "spatium_furniture.glb")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.text)
            Text("glTF Binary (.glb) · \(modelFileSizeText)\(normalizedEnglishName.map { " · \($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(SpatiumTheme.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(SpatiumTheme.warmPanel)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md))
    }
}
