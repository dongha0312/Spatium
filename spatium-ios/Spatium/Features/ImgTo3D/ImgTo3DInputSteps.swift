import SwiftUI
import UIKit

struct ImgTo3DUploadStep: View {
    let image: UIImage?
    let isPreparingImage: Bool
    let convertedFromIncompatibleFormat: Bool
    let canUseCamera: Bool
    let onChoosePhoto: () -> Void
    let onOpenCamera: () -> Void

    var body: some View {
        ImgTo3DStepShell(
            systemImage: "photo.badge.plus",
            title: "가구 사진을 올려주세요",
            description: "3D로 만들 가구의 전체 형태가 잘 보이는 사진 한 장이면 충분해요."
        ) {
            if isPreparingImage {
                preparingImageContent
            } else if let image {
                selectedImageContent(image)
            } else {
                emptyImageContent
            }
        }
    }

    private var preparingImageContent: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            ProgressView()
                .controlSize(.large)
                .tint(SpatiumTheme.accent)
            Text("사진을 최적화하고 있어요…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SpatiumTheme.text)
            Text("화질은 유지하면서 업로드 크기와 메모리 사용을 줄이고 있습니다.")
                .font(.caption)
                .foregroundStyle(SpatiumTheme.soft)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("사진 최적화 중")
    }

    private func selectedImageContent(_ image: UIImage) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 250)
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
                .accessibilityLabel("선택한 가구 사진")
            if convertedFromIncompatibleFormat {
                Label("HEIC 사진을 인식 가능한 PNG로 자동 변환했어요", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.success)
            }
            Spacer(minLength: 0)
            SecondaryButton(
                title: "다른 사진 선택",
                systemImage: "arrow.triangle.2.circlepath",
                action: onChoosePhoto
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyImageContent: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 84, height: 84)
                .background(SpatiumTheme.accent.opacity(0.1), in: Circle())
                .overlay(Circle().stroke(SpatiumTheme.accent.opacity(0.16), lineWidth: 1))
            VStack(spacing: 5) {
                Text("사진 한 장을 선택하세요")
                    .font(.headline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Text("JPG · PNG · HEIC")
                    .font(.caption)
                    .foregroundStyle(SpatiumTheme.soft)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(action: onChoosePhoto) {
                    ImgTo3DPickerActionLabel(title: "사진 보관함", systemImage: "photo.stack")
                }
                .buttonStyle(.pressable)
                if canUseCamera {
                    Button(action: onOpenCamera) {
                        ImgTo3DPickerActionLabel(title: "카메라", systemImage: "camera.fill")
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpatiumTheme.warmPanel.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SpatiumRadius.lg)
                .stroke(SpatiumTheme.accentLight.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
        }
    }
}

struct ImgTo3DNameStep: View {
    @Binding var objectName: String
    @Binding var segmentationProvider: ImgTo3DSegmentationProvider
    @Binding var generationProvider: ImgTo3DGenerationProvider
    @Binding var mcResolution: Int
    @Binding var textureResolution: Int
    @Binding var remesh: ImgTo3DRemesh
    let focusedField: FocusState<ImgTo3DFocusField?>.Binding
    let onObjectNameChanged: () -> Void
    let onSegmentationProviderChanged: () -> Void
    let onGenerationSettingsChanged: () -> Void

    var body: some View {
        ImgTo3DStepShell(
            systemImage: "textformat.abc",
            title: "어떤 가구인가요?",
            description: "GroundingDINO + SAM2가 이 설명을 기준으로 가구를 찾아 분리합니다. 예: 회색 사무용 의자"
        ) {
            ScrollView {
                VStack(spacing: 13) {
                    nameField
                    translationNote
                    segmentationSettings
                    generationSettings
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var nameField: some View {
        TextField("예) 침대 옆 협탁", text: $objectName)
            .focused(focusedField, equals: .objectName)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onChange(of: objectName) { _, _ in onObjectNameChanged() }
            .padding(13)
            .background(SpatiumTheme.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }

    private var translationNote: some View {
        Label("한국어 입력은 분리 과정에서 영어 검색어로 자동 변환됩니다.", systemImage: "character.book.closed")
            .font(.caption)
            .foregroundStyle(SpatiumTheme.soft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segmentationSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("객체 분리 설정")
                .font(.caption.weight(.black))
                .foregroundStyle(SpatiumTheme.soft)
            Picker("객체 분리 모델", selection: $segmentationProvider) {
                ForEach(ImgTo3DSegmentationProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: segmentationProvider) { _, _ in onSegmentationProviderChanged() }
            Text(segmentationProvider == .groundedSAM2
                 ? "객체명을 번역해 GroundingDINO 탐지와 SAM2 마스크를 실행합니다."
                 : "사진 중앙의 주요 객체를 YOLO로 자동 선택합니다.")
                .font(.caption2)
                .foregroundStyle(SpatiumTheme.soft)
        }
        .imgTo3DPipelineSettingsCard()
    }

    private var generationSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("3D 생성 설정")
                .font(.caption.weight(.black))
                .foregroundStyle(SpatiumTheme.soft)
            Picker("3D 생성 모델", selection: $generationProvider) {
                ForEach(ImgTo3DGenerationProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: generationProvider) { _, _ in onGenerationSettingsChanged() }

            if generationProvider == .localTripoSR {
                Picker("메시 해상도", selection: $mcResolution) {
                    Text("192").tag(192)
                    Text("256 (권장)").tag(256)
                    Text("320").tag(320)
                }
                .pickerStyle(.menu)
                .onChange(of: mcResolution) { _, _ in onGenerationSettingsChanged() }
            } else {
                Picker("텍스처 해상도", selection: $textureResolution) {
                    Text("512").tag(512)
                    Text("1024 (권장)").tag(1024)
                    Text("2048").tag(2048)
                }
                .pickerStyle(.menu)
                .onChange(of: textureResolution) { _, _ in onGenerationSettingsChanged() }
                Picker("리메시", selection: $remesh) {
                    ForEach(ImgTo3DRemesh.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: remesh) { _, _ in onGenerationSettingsChanged() }
            }
        }
        .imgTo3DPipelineSettingsCard()
    }
}
