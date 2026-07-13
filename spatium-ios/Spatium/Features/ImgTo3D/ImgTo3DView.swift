import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImgTo3DView: View {
    @State private var step: ImgTo3DStep = .upload
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    /// 서버 전송용으로 정규화된 이미지(HEIC → PNG 변환 포함).
    @State private var uploadImage: ImgTo3DUploadImage.Normalized?
    @State private var showCamera = false
    @State private var showPhotoGallery = false
    @State private var showPhotoPermissionAlert = false

    @State private var objectName = ""
    @State private var normalizedName: ImgTo3DNormalizedName?
    @State private var isNormalizing = false
    @State private var detections: [ImgTo3DDetection] = []
    @State private var selectedDetectionID: Int?
    @State private var isDetecting = false
    @State private var segmentationReady = false
    @State private var showOriginal = false

    @State private var generationProgress = 0.0
    @State private var generated = false
    @State private var viewerMode: ImgTo3DViewerMode = .orbit
    @State private var activeTransformAxis: ImgTo3DTransformAxis = .free
    @State private var snapEnabled = true
    @State private var cameraPreset: ImgTo3DCameraPreset = .perspective
    @State private var autoCorrectionApplied = false
    @State private var cameraResetToken = 0
    @State private var undoHistory: [ImgTo3DCorrectionSnapshot] = []
    @State private var redoHistory: [ImgTo3DCorrectionSnapshot] = []
    @State private var modelTransform = ImgTo3DModelTransform.initial
    @State private var floorSnap = false
    @State private var importedModelURL: URL?
    @State private var importedModelName: String?
    @State private var modelSize = ImgTo3DModelSize()
    @State private var showModelImporter = false

    @State private var saveName = ""
    @State private var category: ImgTo3DCategory = .chair
    @State private var isSaving = false
    @State private var saved = false
    @State private var alertMessage: String?

    private let generationStages = ["이미지 전처리", "TripoSR 메시 생성", "텍스처 베이킹", "GLB 내보내기"]

    var body: some View {
        VStack(spacing: 8) {
            progressHeader

            Card {
                VStack(spacing: 12) {
                    stepContent
                        .id(step)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .frame(maxHeight: .infinity)

                    if !saved {
                        navigationActions
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: step)
            }
            .frame(maxHeight: .infinity)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .task(id: step) {
            await prepareCurrentStep()
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker { selectedImage in
                setImage(selectedImage)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoGallery) {
            GalleryPickerSheet { item in
                photoItem = item
            }
        }
        .fileImporter(
            isPresented: $showModelImporter,
            allowedContentTypes: [UTType(filenameExtension: "glb") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                importedModelURL = urls.first
            case .failure:
                alertMessage = "GLB 파일을 불러오지 못했어요. 파일을 확인해주세요."
            }
        }
        .alert("안내", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("확인", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("사진 접근 권한이 필요해요", isPresented: $showPhotoPermissionAlert) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("가구 사진을 선택하려면 설정에서 Spatium의 사진 접근을 허용해주세요.")
        }
        #if DEBUG
        .onAppear {
            // 스크린샷 검증용: 권한 요청을 포함한 갤러리 열기 흐름을 바로 실행한다.
            if ProcessInfo.processInfo.arguments.contains("-UITestImgTo3DGallery") {
                openGalleryWithPermission()
            }
            // 스크린샷 검증용: -UITestImgTo3DGLB <경로> 로 지정한 GLB를 바로 보정 단계에서 연다.
            // -UITestImgTo3DRotX <도> 를 함께 주면 X축 회전을 미리 적용한 상태로 시작한다(수동 축 보정 재현).
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-UITestImgTo3DGLB"), args.indices.contains(index + 1) {
                importedModelURL = URL(fileURLWithPath: args[index + 1])
                if let rotIndex = args.firstIndex(of: "-UITestImgTo3DRotX"),
                   args.indices.contains(rotIndex + 1),
                   let degrees = Double(args[rotIndex + 1]) {
                    autoCorrectionApplied = true
                    modelTransform.xDegrees = degrees
                    floorSnap = true
                }
                // -UITestImgTo3DCamera front|side|top: 시점 프리셋 화면 검증용
                if let cameraIndex = args.firstIndex(of: "-UITestImgTo3DCamera"),
                   args.indices.contains(cameraIndex + 1),
                   let preset = ImgTo3DCameraPreset.allCases.first(where: { String(describing: $0) == args[cameraIndex + 1] }) {
                    cameraPreset = preset
                    cameraResetToken += 1
                }
                step = .correction
            }
        }
        #endif
    }

    private var progressHeader: some View {
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
                        // 완료·현재 단계가 같은 색이라 구분이 안 되던 것 — 현재 단계에만 옅은 링을 두른다.
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
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(SpatiumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .upload: uploadStep
        case .name: nameStep
        case .detection: detectionStep
        case .segmentation: segmentationStep
        case .generation: generationStep
        case .correction: correctionStep
        case .save: saveStep
        }
    }

    private var uploadStep: some View {
        StepShell(
            systemImage: "photo.badge.plus",
            title: "가구 사진을 올려주세요",
            description: "3D로 만들 가구의 전체 형태가 잘 보이는 사진 한 장이면 충분해요."
        ) {
            if let image {
                VStack(spacing: 14) {
                    Spacer(minLength: 0)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
                        .accessibilityLabel("선택한 가구 사진")
                    if uploadImage?.convertedFromIncompatibleFormat == true {
                        Label("HEIC 사진을 인식 가능한 PNG로 자동 변환했어요", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SpatiumTheme.success)
                    }
                    Spacer(minLength: 0)
                    SecondaryButton(title: "다른 사진 선택", systemImage: "arrow.triangle.2.circlepath") {
                        openGalleryWithPermission()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                        Button { openGalleryWithPermission() } label: {
                            PickerActionLabel(title: "사진 보관함", systemImage: "photo.stack")
                        }
                        .buttonStyle(.pressable)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: {
                                PickerActionLabel(title: "카메라", systemImage: "camera.fill")
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
    }

    private var nameStep: some View {
        StepShell(
            systemImage: "textformat.abc",
            title: "어떤 가구인가요?",
            description: "사진에서 찾을 가구의 이름을 알려주세요. 예: 의자, 책상, 침대 옆 협탁"
        ) {
            VStack(spacing: 13) {
                TextField("예) 침대 옆 협탁", text: $objectName)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { normalizeName() }
                    .onChange(of: objectName) { _, _ in
                        normalizedName = nil
                        detections = []
                        selectedDetectionID = nil
                        resetGeneratedModelState()
                    }
                    .padding(13)
                    .background(SpatiumTheme.elevatedSurface)
                    .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))

                PrimaryButton(
                    title: isNormalizing ? "변환 중…" : "번역 · 정규화",
                    systemImage: "character.book.closed.fill",
                    action: normalizeName
                )
                .disabled(!canNormalize)

                if isNormalizing {
                    LoadingNote(text: "LLM이 객체명을 영어로 정규화하고 있어요…")
                }

                if let normalizedName {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("정규화 결과")
                            .font(.caption.weight(.black))
                            .foregroundStyle(SpatiumTheme.soft)
                        Text("“\(normalizedName.input)” → **\(normalizedName.english)**")
                            .font(.subheadline)
                            .foregroundStyle(SpatiumTheme.text)
                        FlowTags(tags: normalizedName.tags)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(SpatiumTheme.warmPanel)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                }
            }
        }
    }

    private var detectionStep: some View {
        StepShell(
            systemImage: "viewfinder.rectangular",
            title: "가구를 선택해주세요",
            description: "사진에서 찾은 후보 중 3D로 만들 가구 하나를 탭하세요."
        ) {
            if isDetecting {
                LoadingNote(text: "GroundingDINO가 “\(normalizedName?.english ?? "가구")” 객체를 찾고 있어요…")
                    .frame(maxHeight: .infinity)
            } else if let image {
                VStack(spacing: 12) {
                    DetectionImage(
                        image: image,
                        detections: detections,
                        selectedID: selectedDetectionID,
                        onSelect: { id in
                            selectedDetectionID = id
                            segmentationReady = false
                            resetGeneratedModelState()
                            Haptics.selection()
                        }
                    )
                    .frame(maxHeight: 250)
                    Text(selectedDetectionID == nil ? "후보 \(detections.count)개 중 하나를 탭하세요." : "선택 완료! 다음 단계에서 배경을 제거해요.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(selectedDetectionID == nil ? SpatiumTheme.soft : SpatiumTheme.success)
                }
            }
        }
    }

    private var segmentationStep: some View {
        StepShell(
            systemImage: "wand.and.rays",
            title: segmentationReady ? "배경을 제거했어요" : "가구를 분리하고 있어요",
            description: "결과가 마음에 들지 않으면 이전 단계에서 다른 후보를 선택할 수 있어요."
        ) {
            if !segmentationReady {
                LoadingNote(text: "SAM2가 선택한 가구를 분리하고 있어요…")
                    .frame(maxHeight: .infinity)
            } else if let image, let detection = selectedDetection {
                VStack(spacing: 14) {
                    SegmentationImage(image: image, detection: detection, showOriginal: showOriginal)
                        .frame(maxHeight: 230)
                    Toggle("원본 사진 보기", isOn: $showOriginal)
                        .font(.subheadline.weight(.bold))
                        .tint(SpatiumTheme.accent)
                    SecondaryButton(title: "마스크 수정", systemImage: "paintbrush.pointed") {
                        alertMessage = "마스크 브러시 편집은 백엔드 연동 후 지원 예정이에요."
                    }
                }
            }
        }
    }

    private var generationStep: some View {
        StepShell(
            systemImage: generated ? "checkmark.seal.fill" : "cube.transparent.fill",
            title: generated ? "3D 모델이 완성됐어요!" : "3D 모델을 만들고 있어요",
            description: generated ? "다음 단계에서 모델을 확인하고 보정할 수 있어요." : "사진 한 장으로 GLB 모델을 생성하는 중이에요. 잠시만 기다려주세요."
        ) {
            let stage = min(Int(generationProgress / (100 / Double(generationStages.count))), generationStages.count - 1)
            VStack(spacing: 14) {
                HStack(spacing: 5) {
                    ForEach(generationStages.indices, id: \.self) { index in
                        Capsule()
                            .fill(SpatiumTheme.border.opacity(0.55))
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(LinearGradient(colors: [SpatiumTheme.accentLight, SpatiumTheme.accent], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: proxy.size.width * segmentFraction(for: index))
                                }
                            }
                            .frame(height: 7)
                    }
                }
                .animation(.linear(duration: 0.07), value: generationProgress)

                HStack {
                    Text(generated ? "모든 단계 완료" : "\(stage + 1) / \(generationStages.count) 단계 · \(generationStages[stage])")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.soft)
                        .contentTransition(.opacity)
                    Spacer()
                    Text("\(Int(generationProgress))%")
                        .font(.headline.monospacedDigit().weight(.black))
                        .foregroundStyle(SpatiumTheme.accent)
                        .contentTransition(.numericText())
                }

                VStack(spacing: 4) {
                    ForEach(Array(generationStages.enumerated()), id: \.offset) { index, label in
                        let done = generated || index < stage
                        let isCurrent = !generated && index == stage
                        HStack(spacing: 10) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done ? SpatiumTheme.success : isCurrent ? SpatiumTheme.accent : SpatiumTheme.soft)
                                .contentTransition(.symbolEffect(.replace))
                            Text(label)
                                .font(.subheadline.weight(isCurrent ? .bold : .regular))
                                .foregroundStyle(done || isCurrent ? SpatiumTheme.text : SpatiumTheme.soft)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            isCurrent ? SpatiumTheme.elevatedSurface : .clear,
                            in: RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous)
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: done)
                    }
                }
                .padding(7)
                .background(SpatiumTheme.warmPanel.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md))
            }
        }
    }

    /// 전체 진행률(0~100)을 단계별 구간으로 잘라, index번째 세그먼트가 채워진 비율(0~1)을 돌려줍니다.
    private func segmentFraction(for index: Int) -> CGFloat {
        let per = 100.0 / Double(generationStages.count)
        let fraction = (generationProgress - Double(index) * per) / per
        return CGFloat(min(max(fraction, 0), 1))
    }

    private var correctionStep: some View {
        StepShell(
            systemImage: "move.3d",
            title: "가구를 자연스럽게 다듬어주세요",
            description: "기본 보정은 이미 적용했어요. 아래 모드를 고른 뒤 모델을 직접 드래그하면 됩니다."
        ) {
            VStack(spacing: 8) {
                correctionTopBar
                modelCorrectionCanvas
                correctionModeBar
                contextualCorrectionControls
            }
        }
    }

    private var correctionTopBar: some View {
        HStack(spacing: 7) {
            Button {
                recordCorrectionCheckpoint()
                autoAlign()
            } label: {
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

            CorrectionIconButton(systemImage: "arrow.uturn.backward", label: "실행 취소", enabled: !undoHistory.isEmpty, action: undoCorrection)
            CorrectionIconButton(systemImage: "arrow.uturn.forward", label: "다시 실행", enabled: !redoHistory.isEmpty, action: redoCorrection)

            Menu {
                Button("GLB 파일 불러오기", systemImage: "doc.badge.plus") { showModelImporter = true }
                if importedModelName != nil {
                    Button("생성 모델로 돌아가기", systemImage: "cube") {
                        importedModelURL = nil
                        importedModelName = nil
                        modelSize = .init()
                    }
                }
                Divider()
                Button("보정값 초기화", systemImage: "arrow.counterclockwise", action: resetModel)
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

    private var modelCorrectionCanvas: some View {
        ImgTo3DModelViewer(
            transform: $modelTransform,
            mode: viewerMode,
            activeAxis: activeTransformAxis,
            snapEnabled: snapEnabled,
            floorSnap: floorSnap,
            modelURL: importedModelURL,
            cameraPreset: cameraPreset,
            cameraResetToken: cameraResetToken,
            onInteractionBegan: recordCorrectionCheckpoint,
            onModelLoaded: { size, name in
                modelSize = size
                importedModelName = name
                if importedModelURL != nil, name == nil {
                    importedModelURL = nil
                    alertMessage = "GLB 파일을 불러오지 못했어요. 파일을 확인해주세요."
                }
            }
        )
        .frame(maxHeight: .infinity)
        .frame(minHeight: 185)
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
    }

    private var correctionModeBar: some View {
        HStack(spacing: 6) {
            ForEach(ImgTo3DViewerMode.allCases) { mode in
                ModelModeButton(mode: mode, isSelected: viewerMode == mode) {
                    selectViewerMode(mode)
                }
            }
        }
    }

    @ViewBuilder
    private var contextualCorrectionControls: some View {
        switch viewerMode {
        case .orbit:
            CorrectionContextBar(icon: "hand.draw", message: "한 손가락으로 회전하고 두 손가락으로 확대해보세요.") {
                CorrectionQuickButton(title: "시점 초기화", systemImage: "viewfinder") {
                    cameraResetToken += 1
                    Haptics.selection()
                }
            }
        case .move:
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    ForEach(ImgTo3DTransformAxis.allCases) { axis in
                        AxisButton(axis: axis.rawValue, isSelected: activeTransformAxis == axis) {
                            activeTransformAxis = axis
                            if axis == .y { floorSnap = false }
                            Haptics.selection()
                        }
                    }
                    Spacer(minLength: 3)
                    CorrectionQuickButton(title: "가운데", systemImage: "scope") {
                    recordCorrectionCheckpoint()
                    modelTransform.xPosition = 0
                    modelTransform.zPosition = 0
                    Haptics.selection()
                }
                    CorrectionQuickButton(title: floorSnap ? "바닥 고정됨" : "바닥 고정", systemImage: floorSnap ? "checkmark.circle.fill" : "arrow.down.to.line") {
                    recordCorrectionCheckpoint()
                    floorSnap.toggle()
                    if floorSnap { modelTransform.yPosition = 0 }
                    Haptics.selection()
                }
                }
                TransformValuesRow(values: [
                    ("X", modelTransform.xPosition, "m"),
                    ("Y", floorSnap ? 0 : modelTransform.yPosition, "m"),
                    ("Z", modelTransform.zPosition, "m")
                ])
            }
            .padding(8)
            .background(SpatiumTheme.warmPanel.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm))
        case .rotate:
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    ForEach([ImgTo3DTransformAxis.x, .y, .z]) { axis in
                        AxisButton(axis: axis.rawValue, isSelected: activeTransformAxis == axis) {
                            activeTransformAxis = axis
                            Haptics.selection()
                        }
                    }
                    Spacer(minLength: 4)
                    CorrectionQuickButton(title: "−15°", systemImage: "rotate.left") { rotate(axis: activeTransformAxis.rawValue, degrees: -15) }
                    CorrectionQuickButton(title: "+15°", systemImage: "rotate.right") { rotate(axis: activeTransformAxis.rawValue, degrees: 15) }
                    CorrectionQuickButton(title: "+90°", systemImage: "arrow.turn.up.right") { rotate(axis: activeTransformAxis.rawValue, degrees: 90) }
                }
                TransformValuesRow(values: [
                    ("X", modelTransform.xDegrees, "°"),
                    ("Y", modelTransform.yDegrees, "°"),
                    ("Z", modelTransform.zDegrees, "°")
                ])
            }
            .padding(8)
            .background(SpatiumTheme.warmPanel.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm))
        case .scale:
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text("크기")
                        .font(.caption.weight(.black))
                    Slider(
                        value: $modelTransform.scale,
                        in: 0.5...2,
                        step: 0.05,
                        onEditingChanged: { editing in
                            if editing { recordCorrectionCheckpoint() }
                        }
                    )
                    .tint(SpatiumTheme.accent)
                    Text("×\(modelTransform.scale, specifier: "%.2f")")
                        .font(.caption.monospacedDigit().weight(.black))
                        .foregroundStyle(SpatiumTheme.accent)
                        .frame(width: 46)
                    CorrectionQuickButton(title: "원래 크기", systemImage: "1.circle") {
                        recordCorrectionCheckpoint()
                        modelTransform.scale = 1
                        Haptics.selection()
                    }
                }
                Text(modelDimensionText)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(SpatiumTheme.soft)
            }
            .padding(8)
            .background(SpatiumTheme.warmPanel.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm))
        }
    }

    @ViewBuilder
    private var saveStep: some View {
        if saved {
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
                Text("이제 3D 에디터에서 “\(saveName)”을(를) 방에 배치할 수 있어요.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SpatiumTheme.soft)
                Spacer(minLength: 0)
                PrimaryButton(
                    title: "새 모델 만들기",
                    systemImage: "plus.square.on.square",
                    action: resetWizard
                )
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            StepShell(
                systemImage: "square.and.arrow.down.fill",
                title: "마지막으로 확인해주세요",
                description: "저장하면 내 가구 목록에서 바로 사용할 수 있어요."
            ) {
                VStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("가구 이름").font(.subheadline.weight(.bold))
                        TextField("가구 이름", text: $saveName)
                            .padding(13)
                            .background(SpatiumTheme.elevatedSurface)
                            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

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

                    VStack(alignment: .leading, spacing: 5) {
                        Text("생성된 파일")
                            .font(.caption.weight(.black))
                            .foregroundStyle(SpatiumTheme.soft)
                        Text(importedModelName ?? "spatium_furniture.glb")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SpatiumTheme.text)
                        Text("glTF Binary (.glb) · 2.4 MB\(normalizedName.map { " · \($0.english)" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(SpatiumTheme.soft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(SpatiumTheme.warmPanel)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md))

                    Text("현재 웹 기능과 동일한 목업 단계예요. 실제 object storage와 DB 저장은 백엔드 연결 후 활성화됩니다.")
                        .font(.caption)
                        .lineSpacing(3)
                        .foregroundStyle(SpatiumTheme.soft)

                    PrimaryButton(
                        title: isSaving ? "저장 중…" : "가구 목록에 추가",
                        systemImage: "plus.circle.fill",
                        action: saveFurniture
                    )
                    .disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private var navigationActions: some View {
        HStack(spacing: 10) {
            Button {
                if let previous = step.previous {
                    Haptics.selection()
                    step = previous
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.left")
                        .frame(width: 27, height: 27)
                        .background(SpatiumTheme.elevatedSurface, in: Circle())
                    Text("이전")
                }
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(SpatiumTheme.warmPanel)
                    .foregroundStyle(SpatiumTheme.accent)
                    .overlay(Capsule().stroke(SpatiumTheme.border, lineWidth: 1))
                    .clipShape(Capsule())
                    .opacity(step.previous == nil ? 0.35 : 1)
            }
            .buttonStyle(.pressable)
            .disabled(step.previous == nil)

            if let next = step.next {
                Button {
                    if step == .correction, saveName.isEmpty { saveName = objectName }
                    Haptics.impact(.light)
                    step = next
                } label: {
                    HStack(spacing: 9) {
                        Text("다음")
                        Image(systemName: "chevron.right")
                            .frame(width: 27, height: 27)
                            .background(SpatiumTheme.onCta.opacity(0.16), in: Circle())
                    }
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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

    private var canNormalize: Bool {
        !objectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isNormalizing
    }

    private var canAdvance: Bool {
        switch step {
        case .upload: image != nil
        case .name: normalizedName != nil
        case .detection: selectedDetectionID != nil
        case .segmentation: segmentationReady
        case .generation: generated
        case .correction: true
        case .save: false
        }
    }

    private var selectedDetection: ImgTo3DDetection? {
        detections.first { $0.id == selectedDetectionID }
    }

    private var viewerHint: String {
        switch viewerMode {
        case .orbit: "빈 곳을 드래그해 화면 회전 · 핀치로 확대"
        case .move: "가구를 드래그해 바닥 위에서 이동"
        case .rotate: "좌우 드래그로 Y축 · 위아래로 X축 회전"
        case .scale: "위아래로 드래그해 가구 크기 조절"
        }
    }

    private var modelDimensionText: String {
        let scale = modelTransform.scale
        return String(format: "%.2fm × %.2fm × %.2fm", modelSize.width * scale, modelSize.height * scale, modelSize.depth * scale)
    }

    /// 사진 보관함 접근 권한을 확인/요청한 뒤 갤러리 선택 시트를 연다.
    /// 처음이면 시스템 권한 대화상자가 뜨고, 이미 거부된 상태면 설정으로 안내한다.
    private func openGalleryWithPermission() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            showPhotoGallery = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                Task { @MainActor in
                    if status == .authorized || status == .limited {
                        showPhotoGallery = true
                    } else {
                        showPhotoPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showPhotoPermissionAlert = true
        @unknown default:
            showPhotoPermissionAlert = true
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let loadedImage = UIImage(data: data) else {
            alertMessage = "사진을 불러오지 못했어요. 다른 사진을 선택해주세요."
            Haptics.error()
            return
        }
        setImage(loadedImage, rawData: data)
    }

    private func setImage(_ newImage: UIImage, rawData: Data? = nil) {
        image = newImage
        normalizedName = nil
        detections = []
        selectedDetectionID = nil
        segmentationReady = false
        resetGeneratedModelState()
        Haptics.success()

        // PNG 인코딩은 수백 ms 걸릴 수 있어 백그라운드에서 처리한다.
        uploadImage = nil
        Task.detached(priority: .userInitiated) {
            let normalized = ImgTo3DUploadImage.normalize(image: newImage, rawData: rawData)
            await MainActor.run {
                // 처리 중에 다른 사진으로 바뀌었으면 결과를 버린다.
                guard image == newImage else { return }
                uploadImage = normalized
            }
        }
    }

    /// 사진·이름·선택 객체가 바뀌면 그 입력으로 만들었던 이후 결과는 모두 무효입니다.
    /// 이전 모델이 남아 새 결과처럼 보이지 않도록 생성/보정/저장 상태를 한 번에 초기화합니다.
    private func resetGeneratedModelState() {
        generated = false
        generationProgress = 0
        segmentationReady = false
        showOriginal = false
        importedModelURL = nil
        importedModelName = nil
        modelSize = .init()
        modelTransform = .initial
        floorSnap = false
        viewerMode = .orbit
        activeTransformAxis = .free
        snapEnabled = true
        cameraPreset = .perspective
        autoCorrectionApplied = false
        undoHistory.removeAll()
        redoHistory.removeAll()
        saved = false
    }

    private func normalizeName() {
        let input = objectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isNormalizing else { return }
        isNormalizing = true
        normalizedName = nil
        Task {
            defer { isNormalizing = false }
            do {
                normalizedName = try await ImgTo3DMockPipeline.normalize(input)
                Haptics.success()
            } catch is CancellationError {
                return
            } catch {
                alertMessage = "객체명을 변환하지 못했어요. 다시 시도해주세요."
            }
        }
    }

    private func prepareCurrentStep() async {
        switch step {
        case .detection:
            guard detections.isEmpty, let normalizedName else { return }
            isDetecting = true
            do {
                let label = normalizedName.english.split(separator: "/").first.map(String.init) ?? normalizedName.english
                detections = try await ImgTo3DMockPipeline.detect(label: label.trimmingCharacters(in: .whitespaces))
            } catch is CancellationError {
                return
            } catch {
                alertMessage = "사진에서 가구 후보를 찾지 못했어요. 다시 시도해주세요."
            }
            isDetecting = false
        case .segmentation:
            guard !segmentationReady else { return }
            do {
                try await Task.sleep(for: .milliseconds(1_400))
                try Task.checkCancellation()
                segmentationReady = true
            } catch {
                return
            }
        case .generation:
            guard !generated else {
                generationProgress = 100
                return
            }
            do {
                let frameCount = 240
                for frame in 1...frameCount {
                    try await Task.sleep(for: .milliseconds(16))
                    try Task.checkCancellation()
                    generationProgress = Double(frame) / Double(frameCount) * 100
                }
                generated = true
                Haptics.success()
            } catch {
                return
            }
        case .correction:
            guard !autoCorrectionApplied else { return }
            recordCorrectionCheckpoint()
            autoAlign()
            autoCorrectionApplied = true
        default:
            return
        }
    }

    private func rotate(axis: String, degrees: Double) {
        recordCorrectionCheckpoint()
        switch axis {
        case "X": modelTransform.xDegrees += degrees
        case "Y": modelTransform.yDegrees += degrees
        default: modelTransform.zDegrees += degrees
        }
        Haptics.selection()
    }

    private func selectViewerMode(_ mode: ImgTo3DViewerMode) {
        viewerMode = mode
        switch mode {
        case .orbit, .scale:
            activeTransformAxis = .free
        case .move:
            activeTransformAxis = .free
        case .rotate:
            activeTransformAxis = .y
        }
        Haptics.selection()
    }

    private func autoAlign() {
        modelTransform.xDegrees = 0
        modelTransform.zDegrees = 0
        modelTransform.xPosition = 0
        modelTransform.yPosition = 0
        modelTransform.zPosition = 0
        floorSnap = true
        Haptics.success()
    }

    private func resetModel() {
        recordCorrectionCheckpoint()
        modelTransform = .initial
        floorSnap = false
        viewerMode = .orbit
        activeTransformAxis = .free
        cameraPreset = .perspective
        cameraResetToken += 1
        Haptics.selection()
    }

    private var currentCorrectionSnapshot: ImgTo3DCorrectionSnapshot {
        ImgTo3DCorrectionSnapshot(transform: modelTransform, floorSnap: floorSnap)
    }

    private func recordCorrectionCheckpoint() {
        let snapshot = currentCorrectionSnapshot
        guard undoHistory.last != snapshot else { return }
        undoHistory.append(snapshot)
        if undoHistory.count > 30 { undoHistory.removeFirst() }
        redoHistory.removeAll()
    }

    private func undoCorrection() {
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(currentCorrectionSnapshot)
        applyCorrection(previous)
    }

    private func redoCorrection() {
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(currentCorrectionSnapshot)
        applyCorrection(next)
    }

    private func applyCorrection(_ snapshot: ImgTo3DCorrectionSnapshot) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            modelTransform = snapshot.transform
            floorSnap = snapshot.floorSnap
        }
        Haptics.selection()
    }

    private func saveFurniture() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            isSaving = false
            saved = true
            Haptics.success()
        }
    }

    private func resetWizard() {
        step = .upload
        photoItem = nil
        image = nil
        uploadImage = nil
        objectName = ""
        normalizedName = nil
        detections = []
        selectedDetectionID = nil
        segmentationReady = false
        showOriginal = false
        generationProgress = 0
        generated = false
        importedModelURL = nil
        importedModelName = nil
        modelTransform = .initial
        floorSnap = false
        activeTransformAxis = .free
        snapEnabled = true
        cameraPreset = .perspective
        autoCorrectionApplied = false
        undoHistory = []
        redoHistory = []
        cameraResetToken = 0
        saveName = ""
        category = .chair
        saved = false
    }
}

private struct StepShell<Content: View>: View {
    let systemImage: String
    let title: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(LinearGradient(colors: [SpatiumTheme.accentLight, SpatiumTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                        .lineLimit(2)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 갤러리형 사진 선택 시트. 시스템 단일 선택 피커는 한 번 탭하면 바로 확정돼
/// 잘못 누른 사진이 그대로 진행되므로, 인라인 피커(연속 선택)로 체크 표시를 확인한 뒤
/// 하단 버튼으로 확정하는 2단계 선택을 제공한다.
private struct GalleryPickerSheet: View {
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

/// PhotosPicker처럼 Button이 아닌 컨테이너에서도 PrimaryButton과 같은 모습을 내는 라벨.
private struct PickerActionLabel: View {
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

private struct LoadingNote: View {
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

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SpatiumTheme.elevatedSurface, in: Capsule())
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct DetectionImage: View {
    let image: UIImage
    let detections: [ImgTo3DDetection]
    let selectedID: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ForEach(detections) { detection in
                        Button { onSelect(detection.id) } label: {
                            Rectangle()
                                .fill(SpatiumTheme.accent.opacity(selectedID == detection.id ? 0.15 : 0.04))
                                .overlay {
                                    Rectangle().stroke(
                                        selectedID == detection.id ? SpatiumTheme.accent : SpatiumTheme.accentLight,
                                        style: StrokeStyle(lineWidth: selectedID == detection.id ? 3 : 2, dash: selectedID == detection.id ? [] : [6, 4])
                                    )
                                }
                                .overlay(alignment: .topLeading) {
                                    Text("\(Int(detection.score * 100))%")
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(selectedID == detection.id ? SpatiumTheme.accent : .black.opacity(0.62))
                                }
                        }
                        .buttonStyle(.plain)
                        .frame(
                            width: proxy.size.width * detection.width,
                            height: proxy.size.height * detection.height
                        )
                        .position(
                            x: proxy.size.width * (detection.x + detection.width / 2),
                            y: proxy.size.height * (detection.y + detection.height / 2)
                        )
                        .accessibilityLabel("\(detection.label), 정확도 \(Int(detection.score * 100))퍼센트")
                        .accessibilityAddTraits(selectedID == detection.id ? .isSelected : [])
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
    }
}

private struct SegmentationImage: View {
    let image: UIImage
    let detection: ImgTo3DDetection
    let showOriginal: Bool

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
            .overlay {
                if !showOriginal {
                    GeometryReader { proxy in
                        ZStack(alignment: .topLeading) {
                            Checkerboard().frame(width: proxy.size.width, height: proxy.size.height * detection.y)
                            Checkerboard()
                                .frame(width: proxy.size.width, height: proxy.size.height * (1 - detection.y - detection.height))
                                .offset(y: proxy.size.height * (detection.y + detection.height))
                            Checkerboard()
                                .frame(width: proxy.size.width * detection.x, height: proxy.size.height * detection.height)
                                .offset(y: proxy.size.height * detection.y)
                            Checkerboard()
                                .frame(width: proxy.size.width * (1 - detection.x - detection.width), height: proxy.size.height * detection.height)
                                .offset(x: proxy.size.width * (detection.x + detection.width), y: proxy.size.height * detection.y)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border))
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for column in 0..<columns {
                    let color: Color = (row + column).isMultiple(of: 2) ? .white.opacity(0.94) : .gray.opacity(0.82)
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                        with: .color(color)
                    )
                }
            }
        }
    }
}

private struct ModelModeButton: View {
    let mode: ImgTo3DViewerMode
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch mode {
        case .orbit: "rotate.3d"
        case .move: "move.3d"
        case .rotate: "arrow.trianglehead.2.clockwise.rotate.90"
        case .scale: "arrow.up.left.and.arrow.down.right"
        }
    }

    var body: some View {
        Button(action: action) {
            Label(mode.rawValue, systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(isSelected ? SpatiumTheme.onCta : SpatiumTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isSelected ? SpatiumTheme.ctaFill : SpatiumTheme.warmPanel)
                .overlay(Capsule().stroke(isSelected ? .clear : SpatiumTheme.border, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CorrectionIconButton: View {
    let systemImage: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.black))
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 34, height: 34)
                .background(SpatiumTheme.elevatedSurface, in: Circle())
                .overlay(Circle().stroke(SpatiumTheme.border, lineWidth: 1))
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

private struct CorrectionContextBar<Actions: View>: View {
    let icon: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 30, height: 30)
                .background(SpatiumTheme.elevatedSurface, in: Circle())
            Text(message)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SpatiumTheme.soft)
                .lineLimit(2)
            Spacer(minLength: 2)
            actions
        }
        .padding(8)
        .background(SpatiumTheme.warmPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
    }
}

private struct CorrectionQuickButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.black))
                Text(title)
                    .font(.system(size: 8, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(SpatiumTheme.accent)
            .frame(minWidth: 43, minHeight: 34)
            .padding(.horizontal, 3)
            .background(SpatiumTheme.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(SpatiumTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(title)
    }
}

private struct AxisButton: View {
    let axis: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(axis)
                .font(.caption2.monospaced().weight(.black))
                .foregroundStyle(isSelected ? SpatiumTheme.onCta : SpatiumTheme.accent)
                .frame(width: 27, height: 27)
                .background(isSelected ? SpatiumTheme.ctaFill : SpatiumTheme.elevatedSurface, in: Circle())
                .overlay(Circle().stroke(isSelected ? .clear : SpatiumTheme.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(axis)축")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TransformValuesRow: View {
    let values: [(axis: String, value: Double, unit: String)]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    Text(item.axis)
                        .foregroundStyle(axisColor(item.axis))
                    Text(item.value, format: .number.precision(.fractionLength(2)))
                        .foregroundStyle(SpatiumTheme.text)
                    Text(item.unit)
                        .foregroundStyle(SpatiumTheme.soft)
                }
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(SpatiumTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func axisColor(_ axis: String) -> Color {
        switch axis {
        case "X": .red
        case "Y": .green
        default: .blue
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [SpatiumTheme.background, SpatiumTheme.backgroundGradientMid, SpatiumTheme.backgroundGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        ImgTo3DView()
            .padding(12)
    }
}
