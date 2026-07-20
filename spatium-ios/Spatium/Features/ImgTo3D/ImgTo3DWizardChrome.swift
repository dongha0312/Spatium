import PhotosUI
import SwiftUI

enum ImgTo3DFocusField: Hashable {
    case objectName
    case saveName
}

extension View {
    func imgTo3DPipelineSettingsCard() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpatiumTheme.warmPanel.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
    }
}

struct ImgTo3DProgressHeader: View {
    let step: ImgTo3DStep
    let usesCompactHeight: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("STEP \(step.rawValue + 1) / \(ImgTo3DStep.allCases.count)")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(SpatiumTheme.accent)
                Text(step.title)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                ForEach(ImgTo3DStep.allCases) { item in
                    ZStack {
                        Circle()
                            .fill(item.rawValue <= step.rawValue ? SpatiumTheme.accent : SpatiumTheme.elevatedSurface)
                        if item.rawValue < step.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(item.rawValue + 1)")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(item.rawValue == step.rawValue ? .white : SpatiumTheme.soft)
                        }
                    }
                    .frame(width: 19, height: 19)
                    .overlay {
                        if item == step {
                            Circle()
                                .stroke(SpatiumTheme.accent.opacity(0.35), lineWidth: 2.5)
                                .padding(-3)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.rawValue + 1)단계, \(item.title)")
                    .accessibilityAddTraits(item == step ? .isSelected : [])
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
        }
        .padding(.horizontal, usesCompactHeight ? 10 : 13)
        .padding(.vertical, usesCompactHeight ? 5 : 9)
        .background(SpatiumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border, lineWidth: 1))
    }
}

struct ImgTo3DNavigationActions: View {
    let step: ImgTo3DStep
    let canAdvance: Bool
    let usesCompactHeight: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if step.previous != nil {
                Button(action: onPrevious) {
                    HStack(spacing: 9) {
                        Image(systemName: "chevron.left")
                            .frame(width: 27, height: 27)
                            .background(SpatiumTheme.elevatedSurface, in: Circle())
                        Text("이전")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, usesCompactHeight ? 8 : 12)
                    .background(SpatiumTheme.warmPanel)
                    .foregroundStyle(SpatiumTheme.accent)
                    .overlay(Capsule().stroke(SpatiumTheme.border, lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }

            if step.next != nil {
                Button(action: onNext) {
                    HStack(spacing: 9) {
                        Text("다음")
                        Image(systemName: "chevron.right")
                            .frame(width: 27, height: 27)
                            .background(SpatiumTheme.onCta.opacity(0.16), in: Circle())
                    }
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, usesCompactHeight ? 8 : 12)
                    .background(SpatiumTheme.ctaFill)
                    .foregroundStyle(SpatiumTheme.onCta)
                    .clipShape(Capsule())
                    .opacity(canAdvance ? 1 : 0.4)
                }
                .buttonStyle(.pressable)
                .disabled(!canAdvance)
            }
        }
    }
}

struct ImgTo3DStepShell<Content: View>: View {
    let systemImage: String
    let title: String
    let description: String
    @ViewBuilder let content: Content

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var usesCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactHeight ? 6 : 10) {
            HStack(alignment: .top, spacing: usesCompactHeight ? 7 : 9) {
                Image(systemName: systemImage)
                    .font((usesCompactHeight ? Font.caption : Font.subheadline).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: usesCompactHeight ? 28 : 34, height: usesCompactHeight ? 28 : 34)
                    .background(LinearGradient(
                        colors: [SpatiumTheme.accentLight, SpatiumTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font((usesCompactHeight ? Font.subheadline : Font.headline).weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text(description)
                        .font(usesCompactHeight ? .caption2 : .caption)
                        .foregroundStyle(SpatiumTheme.soft)
                        .lineLimit(usesCompactHeight ? 1 : 2)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct GalleryPickerSheet: View {
    var onPicked: (PhotosPickerItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            PhotosPicker(
                selection: $selection,
                maxSelectionCount: 1,
                selectionBehavior: .continuous,
                matching: .images
            ) {
                Text("사진 보관함")
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .photosPickerAccessoryVisibility(.hidden, edges: .bottom)
            .navigationTitle("사진 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SpatiumTheme.accent)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(title: "이 사진 사용", systemImage: "checkmark") {
                    guard let item = selection.first else { return }
                    onPicked(item)
                    dismiss()
                }
                .disabled(selection.isEmpty)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.thinMaterial)
            }
        }
    }
}

struct ImgTo3DPickerActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(SpatiumTheme.onCta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(SpatiumTheme.ctaFill)
            .clipShape(Capsule())
    }
}

struct ImgTo3DLoadingNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(SpatiumTheme.accent)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpatiumTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(SpatiumTheme.warmPanel)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md))
    }
}
