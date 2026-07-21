import SwiftUI

struct ImgTo3DCorrectionStep: View {
    @Binding var modelTransform: ImgTo3DModelTransform
    @Binding var floorSnap: Bool
    @Binding var viewerMode: ImgTo3DViewerMode
    @Binding var activeTransformAxis: ImgTo3DTransformAxis
    @Binding var cameraPreset: ImgTo3DCameraPreset
    @Binding var cameraResetToken: Int
    @Binding var importedModelURL: URL?
    @Binding var importedModelName: String?
    @Binding var modelSize: ImgTo3DModelSize
    @Binding var showModelImporter: Bool

    let autoAlignToken: Int
    let canUndo: Bool
    let canRedo: Bool
    let usesCompactHeight: Bool
    let onCheckpoint: () -> Void
    let onAutoAlign: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onReset: () -> Void
    let onRotate: (String, Double) -> Void
    let onSelectMode: (ImgTo3DViewerMode) -> Void
    let onModelLoadFailure: () -> Void

    private var viewerHint: String {
        switch viewerMode {
        case .orbit: "빈 곳을 드래그해 화면 회전 · 핀치로 확대"
        case .move: "가구를 드래그해 바닥 위에서 이동"
        case .rotate: "좌우 드래그로 Y축 · 위아래로 X축 회전"
        case .scale: "위아래로 드래그해 가구 크기 조절"
        }
    }

    private var modelDimensionText: String {
        String(format: "%.2fm × %.2fm × %.2fm", modelSize.width, modelSize.height, modelSize.depth)
    }

    var body: some View {
        ImgTo3DStepShell(
            systemImage: "move.3d",
            title: "가구를 자연스럽게 다듬어주세요",
            description: "기본 보정은 이미 적용했어요. 아래 모드를 고른 뒤 모델을 직접 드래그하면 됩니다."
        ) {
            if usesCompactHeight {
                compactContent
            } else {
                regularContent
            }
        }
    }

    private var compactContent: some View {
        HStack(alignment: .top, spacing: 10) {
            modelCanvas
                .frame(minWidth: 280)
            ScrollView {
                controlStack(spacing: 7)
            }
            .scrollIndicators(.hidden)
            .frame(minWidth: 270, idealWidth: 320, maxWidth: 360)
        }
    }

    private var regularContent: some View {
        VStack(spacing: 8) {
            correctionTopBar
            modelCanvas
            correctionModeBar
            contextualControls
                .id(viewerMode)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func controlStack(spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            correctionTopBar
            correctionModeBar
            contextualControls
                .id(viewerMode)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var correctionTopBar: some View {
        HStack(spacing: 7) {
            Button(action: applyAutoAlignment) {
                Label("자동 보정", systemImage: "wand.and.stars")
                    .font(.caption.weight(.black))
                    .foregroundStyle(SpatiumTheme.onCta)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(SpatiumTheme.ctaFill)
                    .clipShape(Capsule())
            }
            .buttonStyle(.pressable)

            Spacer(minLength: 2)

            ImgTo3DCorrectionIconButton(
                systemImage: "arrow.uturn.backward",
                label: "실행 취소",
                enabled: canUndo,
                action: onUndo
            )
            ImgTo3DCorrectionIconButton(
                systemImage: "arrow.uturn.forward",
                label: "다시 실행",
                enabled: canRedo,
                action: onRedo
            )

            Menu {
                Button("GLB 파일 불러오기", systemImage: "doc.badge.plus") {
                    showModelImporter = true
                }
                if importedModelName != nil {
                    Button("생성 모델로 돌아가기", systemImage: "cube", action: restoreGeneratedModel)
                }
                Divider()
                Button("보정값 초기화", systemImage: "arrow.counterclockwise", action: onReset)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.black))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(SpatiumTheme.elevatedSurface, in: Circle())
                    .overlay(Circle().stroke(SpatiumTheme.border, lineWidth: 1))
            }
        }
    }

    private var modelCanvas: some View {
        ImgTo3DModelViewer(
            transform: $modelTransform,
            mode: viewerMode,
            activeAxis: activeTransformAxis,
            floorSnap: floorSnap,
            modelURL: importedModelURL,
            cameraPreset: cameraPreset,
            cameraResetToken: cameraResetToken,
            autoAlignToken: autoAlignToken,
            onInteractionBegan: onCheckpoint,
            onModelLoaded: handleModelLoaded,
            onModelBoundsChanged: { modelSize = $0 },
            onAutoAlignment: handleAutoAlignment
        )
        .frame(maxHeight: .infinity)
        .frame(minHeight: usesCompactHeight ? 118 : 185)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
        .overlay(alignment: .bottom) {
            Label(viewerHint, systemImage: viewerMode.hintSystemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.58), in: Capsule())
                .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            cameraMenu
        }
        .accessibilityIdentifier("img-to-3d-model-canvas")
    }

    private var cameraMenu: some View {
        Menu {
            ForEach(ImgTo3DCameraPreset.allCases) { preset in
                Button(preset.rawValue, systemImage: preset.systemImage) {
                    cameraPreset = preset
                    cameraResetToken += 1
                    Haptics.selection()
                }
            }
        } label: {
            Image(systemName: "viewfinder")
                .font(.subheadline.weight(.black))
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .padding(8)
        .accessibilityLabel("뷰포트 시점 선택")
    }

    private var correctionModeBar: some View {
        HStack(spacing: 6) {
            ForEach(ImgTo3DViewerMode.allCases) { mode in
                ImgTo3DModelModeButton(mode: mode, isSelected: viewerMode == mode) {
                    onSelectMode(mode)
                }
            }
        }
    }

    @ViewBuilder
    private var contextualControls: some View {
        switch viewerMode {
        case .orbit:
            ImgTo3DCorrectionContextBar(
                icon: "hand.draw",
                message: "한 손가락으로 회전하고 두 손가락으로 확대해보세요."
            ) {
                ImgTo3DCorrectionQuickButton(title: "시점 초기화", systemImage: "viewfinder", action: resetCamera)
            }
        case .move:
            moveControls
        case .rotate:
            rotateControls
        case .scale:
            scaleControls
        }
    }

    private var moveControls: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                ForEach(ImgTo3DTransformAxis.allCases) { axis in
                    ImgTo3DAxisButton(axis: axis.rawValue, isSelected: activeTransformAxis == axis) {
                        activeTransformAxis = axis
                        if axis == .y { floorSnap = false }
                        Haptics.selection()
                    }
                }
                Spacer(minLength: 3)
                ImgTo3DCorrectionQuickButton(title: "가운데", systemImage: "scope", action: centerModel)
                ImgTo3DCorrectionQuickButton(
                    title: floorSnap ? "바닥 고정됨" : "바닥 고정",
                    systemImage: floorSnap ? "checkmark.circle.fill" : "arrow.down.to.line",
                    action: toggleFloorSnap
                )
            }
            ImgTo3DTransformValuesRow(values: [
                ("X", modelTransform.xPosition, "m"),
                ("Y", floorSnap ? 0 : modelTransform.yPosition, "m"),
                ("Z", modelTransform.zPosition, "m")
            ])
        }
        .padding(8)
        .background(SpatiumTheme.warmPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm))
    }

    private var rotateControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach([ImgTo3DTransformAxis.x, .y, .z]) { axis in
                    ImgTo3DAxisButton(axis: axis.rawValue, isSelected: activeTransformAxis == axis) {
                        activeTransformAxis = axis
                        Haptics.selection()
                    }
                }
                Spacer(minLength: 4)
                ImgTo3DCorrectionQuickButton(title: "−15°", systemImage: "rotate.left") {
                    onRotate(activeTransformAxis.rawValue, -15)
                }
                ImgTo3DCorrectionQuickButton(title: "+15°", systemImage: "rotate.right") {
                    onRotate(activeTransformAxis.rawValue, 15)
                }
                ImgTo3DCorrectionQuickButton(title: "+90°", systemImage: "arrow.turn.up.right") {
                    onRotate(activeTransformAxis.rawValue, 90)
                }
            }
            ImgTo3DTransformValuesRow(values: [
                ("X", modelTransform.xDegrees, "°"),
                ("Y", modelTransform.yDegrees, "°"),
                ("Z", modelTransform.zDegrees, "°")
            ])
        }
        .padding(8)
        .background(SpatiumTheme.warmPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm))
    }

    private var scaleControls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("크기")
                    .font(.caption.weight(.black))
                Slider(
                    value: $modelTransform.scale,
                    in: 0.5...2,
                    step: 0.05,
                    onEditingChanged: { if $0 { onCheckpoint() } }
                )
                .tint(SpatiumTheme.accent)
                Text("×\(modelTransform.scale, specifier: "%.2f")")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 46)
                ImgTo3DCorrectionQuickButton(title: "원래 크기", systemImage: "1.circle", action: resetScale)
            }
            Text(modelDimensionText)
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(SpatiumTheme.soft)
        }
        .padding(8)
        .background(SpatiumTheme.warmPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm))
    }

    private func applyAutoAlignment() {
        onCheckpoint()
        onAutoAlign()
    }

    private func restoreGeneratedModel() {
        importedModelURL = nil
        importedModelName = nil
        modelSize = .init()
    }

    private func handleModelLoaded(size: ImgTo3DModelSize, name: String?) {
        modelSize = size
        importedModelName = name
        if importedModelURL != nil, name == nil {
            importedModelURL = nil
            onModelLoadFailure()
        }
    }

    private func handleAutoAlignment(_ alignedTransform: ImgTo3DModelTransform) {
        modelTransform = alignedTransform
        floorSnap = true
        Haptics.success()
    }

    private func resetCamera() {
        cameraResetToken += 1
        Haptics.selection()
    }

    private func centerModel() {
        onCheckpoint()
        modelTransform.xPosition = 0
        modelTransform.zPosition = 0
        Haptics.selection()
    }

    private func toggleFloorSnap() {
        onCheckpoint()
        floorSnap.toggle()
        if floorSnap { modelTransform.yPosition = 0 }
        Haptics.selection()
    }

    private func resetScale() {
        onCheckpoint()
        modelTransform.scale = 1
        Haptics.selection()
    }
}
