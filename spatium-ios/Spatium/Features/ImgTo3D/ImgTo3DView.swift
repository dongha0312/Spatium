import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImgTo3DView: View {
    var onFurnitureSaved: () -> Void
    private let initialCategory: ImgTo3DCategory
    private let isActive: Bool

    @EnvironmentObject private var userFurnitureStore: UserFurnitureStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: ImgTo3DStep = .upload
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    /// 서버 전송용으로 정규화된 이미지(HEIC → PNG 변환 포함).
    @State private var uploadImage: ImgTo3DUploadImage.Normalized?
    @State private var isPreparingImage = false
    @State private var isRestoringImages = false
    @State private var imageRestorationID: UUID?
    @State private var imagePreparationID: UUID?
    @State private var imagePreparationTask: Task<Void, Never>?
    @State private var showCamera = false
    @State private var showPhotoGallery = false
    @State private var showPhotoPermissionAlert = false

    @State private var objectName = ""
    @State private var normalizedName: ImgTo3DNormalizedName?
    @State private var segmentationReady = false
    @State private var isSegmenting = false
    @State private var segmentedImage: UIImage?
    @State private var segmentedPNG: Data?
    @State private var segmentationResult: ImgTo3DSegmentationResult?
    @State private var segmentationError: String?
    @State private var showOriginal = false
    @State private var segmentationProvider: ImgTo3DSegmentationProvider = .groundedSAM2

    @State private var generationProgress = 0.0
    @State private var generated = false
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generationProvider: ImgTo3DGenerationProvider = .localTripoSR
    @State private var mcResolution = 256
    @State private var textureResolution = 1024
    @State private var remesh: ImgTo3DRemesh = .none
    @State private var viewerMode: ImgTo3DViewerMode = .orbit
    @State private var activeTransformAxis: ImgTo3DTransformAxis = .free
    @State private var cameraPreset: ImgTo3DCameraPreset = .perspective
    @State private var autoCorrectionApplied = false
    @State private var autoAlignToken = 0
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
    @State private var category: ImgTo3DCategory = .bathtub
    @State private var isSaving = false
    @State private var saved = false
    @State private var saveNotice: String?
    @State private var alertMessage: String?
    @FocusState private var focusedField: ImgTo3DFocusField?

    private var generationStages: [String] {
        ["이미지 전처리", "\(generationProvider.title) 메시 생성", "텍스처 베이킹", "GLB 내보내기"]
    }

    private var usesCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    /// 메인 탭은 전환 애니메이션과 진행 상태 유지를 위해 이 화면을 ZStack에 계속 보관합니다.
    /// 실제로 보이는 동안에만 디코딩 이미지와 SceneKit 뷰를 유지해 숨은 탭의 메모리 점유를 줄입니다.
    private var keepsTransientResourcesActive: Bool {
        isActive && scenePhase == .active
    }

    private var transientImageTaskID: String {
        "\(step.rawValue)-\(keepsTransientResourcesActive)"
    }

    init(
        initialCategory: ImgTo3DCategory = .bathtub,
        isActive: Bool = true,
        onFurnitureSaved: @escaping () -> Void = {}
    ) {
        self.onFurnitureSaved = onFurnitureSaved
        self.initialCategory = initialCategory
        self.isActive = isActive
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        VStack(spacing: 8) {
            ImgTo3DProgressHeader(step: step, usesCompactHeight: usesCompactHeight)

            Card {
                VStack(spacing: usesCompactHeight ? 7 : 12) {
                    responsiveStepContent
                        .id(step)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .frame(maxHeight: .infinity)

                    if !saved {
                        ImgTo3DNavigationActions(
                            step: step,
                            canAdvance: canAdvance,
                            usesCompactHeight: usesCompactHeight,
                            onPrevious: goToPreviousStep,
                            onNext: goToNextStep
                        )
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: step)
            }
            .frame(maxHeight: .infinity)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            beginLoadingPhoto(item)
        }
        .onChange(of: step) { _, _ in
            focusedField = nil
        }
        .task(id: step) {
            await prepareCurrentStep()
        }
        .task(id: transientImageTaskID) {
            guard keepsTransientResourcesActive else { return }
            await restoreTransientImagesIfNeeded(for: step)
        }
        .onChange(of: keepsTransientResourcesActive) { _, isActive in
            if !isActive {
                releaseTransientResources()
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker { selectedImage in
                beginPreparingCameraImage(selectedImage)
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
        .onDisappear {
            releaseTransientResources(cancelImagePreparation: true)
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
            if args.contains("-UITestImgTo3DName") {
                image = UIImage(systemName: "chair.fill")
                step = .name
            }
            if let index = args.firstIndex(of: "-UITestImgTo3DGLB"), args.indices.contains(index + 1) {
                let requestedModel = args[index + 1]
                let requestedURL = URL(fileURLWithPath: requestedModel)
                importedModelURL = FileManager.default.fileExists(atPath: requestedURL.path)
                    ? requestedURL
                    : Bundle.main.url(
                        forResource: requestedURL.deletingPathExtension().lastPathComponent,
                        withExtension: requestedURL.pathExtension.isEmpty ? "glb" : requestedURL.pathExtension
                    )
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

    @ViewBuilder
    private var responsiveStepContent: some View {
        if usesCompactHeight, step != .correction, step != .name {
            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        } else {
            stepContent
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .upload:
            ImgTo3DUploadStep(
                image: image,
                isPreparingImage: isPreparingImage || isRestoringImages,
                convertedFromIncompatibleFormat: uploadImage?.convertedFromIncompatibleFormat == true,
                canUseCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
                onChoosePhoto: openGalleryWithPermission,
                onOpenCamera: { showCamera = true }
            )
        case .name:
            ImgTo3DNameStep(
                objectName: $objectName,
                segmentationProvider: $segmentationProvider,
                generationProvider: $generationProvider,
                mcResolution: $mcResolution,
                textureResolution: $textureResolution,
                remesh: $remesh,
                focusedField: $focusedField,
                onObjectNameChanged: handleObjectNameChanged,
                onSegmentationProviderChanged: resetGeneratedModelState,
                onGenerationSettingsChanged: resetGenerationResult
            )
        case .segmentation:
            ImgTo3DSegmentationStep(
                isReady: segmentationReady,
                isSegmenting: isSegmenting,
                provider: segmentationProvider,
                originalImage: image,
                segmentedImage: segmentedImage,
                result: segmentationResult,
                errorMessage: segmentationError,
                showOriginal: $showOriginal,
                onRetry: retrySegmentation
            )
        case .generation:
            ImgTo3DGenerationStep(
                progress: generationProgress,
                generated: generated,
                isGenerating: isGenerating,
                errorMessage: generationError,
                stages: generationStages,
                onRetry: retryGeneration
            )
        case .correction:
            if keepsTransientResourcesActive {
                ImgTo3DCorrectionStep(
                    modelTransform: $modelTransform,
                    floorSnap: $floorSnap,
                    viewerMode: $viewerMode,
                    activeTransformAxis: $activeTransformAxis,
                    cameraPreset: $cameraPreset,
                    cameraResetToken: $cameraResetToken,
                    importedModelURL: $importedModelURL,
                    importedModelName: $importedModelName,
                    modelSize: $modelSize,
                    showModelImporter: $showModelImporter,
                    autoAlignToken: autoAlignToken,
                    canUndo: !undoHistory.isEmpty,
                    canRedo: !redoHistory.isEmpty,
                    usesCompactHeight: usesCompactHeight,
                    onCheckpoint: recordCorrectionCheckpoint,
                    onAutoAlign: autoAlign,
                    onUndo: undoCorrection,
                    onRedo: redoCorrection,
                    onReset: resetModel,
                    onRotate: { axis, degrees in
                        rotate(axis: axis, degrees: degrees)
                    },
                    onSelectMode: selectViewerMode,
                    onModelLoadFailure: {
                        alertMessage = "GLB 파일을 불러오지 못했어요. 파일을 확인해주세요."
                    }
                )
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        case .save:
            ImgTo3DSaveStep(
                saveName: $saveName,
                category: $category,
                focusedField: $focusedField,
                saved: saved,
                isSaving: isSaving,
                saveNotice: saveNotice,
                importedModelName: importedModelName,
                modelFileSizeText: modelFileSizeText,
                normalizedEnglishName: normalizedName?.english,
                onSave: saveFurniture,
                onReset: resetWizard
            )
        }
    }

    private func handleObjectNameChanged() {
        normalizedName = nil
        resetGeneratedModelState()
    }

    private func retrySegmentation() {
        Task { await runSegmentation() }
    }

    private func retryGeneration() {
        Task { await runGeneration() }
    }

    private func goToPreviousStep() {
        guard let previous = step.previous else { return }
        Haptics.selection()
        step = previous
    }

    private func goToNextStep() {
        guard let next = step.next, canAdvance else { return }
        if step == .correction, saveName.isEmpty {
            saveName = objectName
        }
        Haptics.impact(.light)
        step = next
    }

    private var canAdvance: Bool {
        switch step {
        case .upload: image != nil && uploadImage != nil && !isPreparingImage && !isRestoringImages
        case .name: !objectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .segmentation: segmentationReady
        case .generation: generated
        case .correction: true
        case .save: false
        }
    }

    private var modelFileSizeText: String {
        guard let importedModelURL,
              let size = try? importedModelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return "-"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
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

    private func beginLoadingPhoto(_ item: PhotosPickerItem) {
        let requestID = beginImagePreparation()
        imagePreparationTask = Task {
            await loadPhoto(item, requestID: requestID)
        }
    }

    private func beginPreparingCameraImage(_ cameraImage: UIImage) {
        let requestID = beginImagePreparation()
        imagePreparationTask = Task {
            await loadCameraImage(cameraImage, requestID: requestID)
        }
    }

    private func beginImagePreparation() -> UUID {
        imagePreparationTask?.cancel()
        let requestID = UUID()
        imagePreparationID = requestID
        isPreparingImage = true
        return requestID
    }

    private func loadPhoto(_ item: PhotosPickerItem, requestID: UUID) async {
        defer { finishImagePreparation(requestID: requestID) }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                reportImagePreparationFailure(requestID: requestID)
                return
            }
            try Task.checkCancellation()
            let prepared = await ImgTo3DUploadImage.prepareInBackground(rawData: data)
            try Task.checkCancellation()
            guard imagePreparationID == requestID else { return }
            guard let prepared else {
                reportImagePreparationFailure(requestID: requestID)
                return
            }
            applyPreparedImage(prepared)
        } catch is CancellationError {
            return
        } catch {
            reportImagePreparationFailure(requestID: requestID)
        }
    }

    private func loadCameraImage(_ cameraImage: UIImage, requestID: UUID) async {
        defer { finishImagePreparation(requestID: requestID) }
        let prepared = await ImgTo3DUploadImage.prepareInBackground(cameraImage: cameraImage)
        guard !Task.isCancelled, imagePreparationID == requestID else { return }
        guard let prepared else {
            reportImagePreparationFailure(requestID: requestID)
            return
        }
        applyPreparedImage(prepared)
    }

    private func applyPreparedImage(_ prepared: ImgTo3DUploadImage.Prepared) {
        image = keepsTransientResourcesActive ? prepared.previewImage : nil
        uploadImage = prepared.upload
        normalizedName = nil
        segmentationReady = false
        resetGeneratedModelState()
        Haptics.success()
    }

    private func reportImagePreparationFailure(requestID: UUID) {
        guard imagePreparationID == requestID else { return }
        alertMessage = "사진을 불러오지 못했어요. 다른 사진을 선택해주세요."
        Haptics.error()
    }

    private func finishImagePreparation(requestID: UUID) {
        guard imagePreparationID == requestID else { return }
        isPreparingImage = false
        imagePreparationID = nil
        imagePreparationTask = nil
    }

    /// 탭 이동·백그라운드 진입 때 화면 표시용 UIImage만 해제합니다.
    /// 서버 전송용 압축 Data와 처리 결과, 생성된 GLB URL은 남겨 진행 상태를 그대로 복원합니다.
    private func releaseTransientResources(cancelImagePreparation: Bool = false) {
        if cancelImagePreparation {
            imagePreparationTask?.cancel()
            imagePreparationTask = nil
            imagePreparationID = nil
            isPreparingImage = false
        }
        imageRestorationID = nil
        isRestoringImages = false
        image = nil
        segmentedImage = nil
    }

    /// 필요한 단계에서만 보관 중인 압축 Data를 작은 화면용 이미지로 다시 디코딩합니다.
    /// 복원 중 탭이나 단계가 바뀌면 오래된 작업의 결과를 적용하지 않습니다.
    private func restoreTransientImagesIfNeeded(for requestedStep: ImgTo3DStep) async {
        let originalData: Data? = {
            guard image == nil,
                  requestedStep == .upload || requestedStep == .segmentation else { return nil }
            return uploadImage?.data
        }()
        let resultData: Data? = {
            guard segmentedImage == nil, requestedStep == .segmentation else { return nil }
            return segmentedPNG ?? segmentationResult?.imageData
        }()
        guard originalData != nil || resultData != nil else { return }

        let requestID = UUID()
        imageRestorationID = requestID
        isRestoringImages = true
        defer {
            if imageRestorationID == requestID {
                imageRestorationID = nil
                isRestoringImages = false
            }
        }

        if let originalData {
            let restored = await ImgTo3DUploadImage.previewInBackground(rawData: originalData)
            guard !Task.isCancelled,
                  imageRestorationID == requestID,
                  keepsTransientResourcesActive,
                  step == requestedStep else { return }
            if image == nil {
                image = restored
            }
        }

        if let resultData {
            let restored = await ImgTo3DUploadImage.previewInBackground(rawData: resultData)
            guard !Task.isCancelled,
                  imageRestorationID == requestID,
                  keepsTransientResourcesActive,
                  step == requestedStep else { return }
            if segmentedImage == nil {
                segmentedImage = restored
            }
        }
    }

    /// 사진·이름·선택 객체가 바뀌면 그 입력으로 만들었던 이후 결과는 모두 무효입니다.
    /// 이전 모델이 남아 새 결과처럼 보이지 않도록 생성/보정/저장 상태를 한 번에 초기화합니다.
    private func resetGeneratedModelState() {
        segmentationReady = false
        isSegmenting = false
        segmentedImage = nil
        segmentedPNG = nil
        segmentationResult = nil
        segmentationError = nil
        showOriginal = false
        resetGenerationResult()
        saveName = ""
    }

    private func resetGenerationResult() {
        generated = false
        generationProgress = 0
        isGenerating = false
        generationError = nil
        importedModelURL = nil
        importedModelName = nil
        modelSize = .init()
        modelTransform = .initial
        floorSnap = false
        viewerMode = .orbit
        activeTransformAxis = .free
        cameraPreset = .perspective
        autoCorrectionApplied = false
        undoHistory.removeAll()
        redoHistory.removeAll()
        saved = false
    }

    private func prepareCurrentStep() async {
        switch step {
        case .segmentation:
            await runSegmentation()
        case .generation:
            await runGeneration()
        case .correction:
            guard !autoCorrectionApplied else { return }
            recordCorrectionCheckpoint()
            autoAlign()
            autoCorrectionApplied = true
        default:
            return
        }
    }

    private func runSegmentation() async {
        guard !segmentationReady, !isSegmenting,
              !objectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let payload = uploadImage else {
            segmentationError = "업로드 이미지를 준비하지 못했습니다."
            return
        }
        isSegmenting = true
        defer { isSegmenting = false }
        segmentationError = nil
        do {
            let result = try await ImgTo3DService().removeBackground(
                image: payload,
                objectQuery: objectName.trimmingCharacters(in: .whitespacesAndNewlines),
                provider: segmentationProvider
            )
            try Task.checkCancellation()
            var resultImage: UIImage?
            if keepsTransientResourcesActive {
                resultImage = await ImgTo3DUploadImage.previewInBackground(rawData: result.imageData)
                try Task.checkCancellation()
                if keepsTransientResourcesActive, resultImage == nil {
                    throw ImgTo3DServiceError.invalidResponse
                }
            }
            segmentationResult = result
            segmentedPNG = result.imageData
            segmentedImage = keepsTransientResourcesActive ? resultImage : nil
            normalizedName = ImgTo3DNormalizedName(
                input: objectName,
                english: result.translatedQuery ?? result.segmentedObject,
                tags: [result.segmentedObject]
            )
            segmentationReady = true
            Haptics.success()
        } catch is CancellationError {
            return
        } catch {
            segmentationError = error.localizedDescription
            Haptics.error()
        }
    }

    private func runGeneration() async {
        guard !generated, !isGenerating, let segmentedPNG else { return }
        isGenerating = true
        generationError = nil
        generationProgress = max(generationProgress, 2)
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(450))
                if Task.isCancelled { return }
                generationProgress = min(generationProgress + 2.5, 92)
            }
        }
        defer {
            progressTask.cancel()
            isGenerating = false
        }
        do {
            let result = try await ImgTo3DService().generateModel(
                segmentedPNG: segmentedPNG,
                provider: generationProvider,
                mcResolution: mcResolution,
                textureResolution: textureResolution,
                remesh: remesh
            )
            try Task.checkCancellation()
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Spatium/GeneratedModels", isDirectory: true)
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("SpatiumGeneratedModels", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = URL(fileURLWithPath: result.fileName).lastPathComponent
            let modelURL = directory.appendingPathComponent(safeName.isEmpty ? "\(result.id).glb" : safeName)
            try result.modelData.write(to: modelURL, options: .atomic)
            importedModelURL = modelURL
            importedModelName = modelURL.lastPathComponent
            generationProgress = 100
            generated = true
            Haptics.success()
        } catch is CancellationError {
            return
        } catch {
            generationError = error.localizedDescription
            Haptics.error()
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            viewerMode = mode
            switch mode {
            case .orbit, .move, .scale:
                activeTransformAxis = .free
            case .rotate:
                activeTransformAxis = .y
            }
        }
        Haptics.selection()
    }

    private func autoAlign() {
        autoAlignToken &+= 1
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
        saveNotice = nil
        Task {
            do {
                let correctedModelURL = try makeCorrectedModelURL()
                let furniture = try await userFurnitureStore.save(
                    name: saveName,
                    normalizedName: normalizedName?.english ?? saveName,
                    category: category.code,
                    categoryLabel: category.rawValue,
                    width: modelSize.width,
                    height: modelSize.height,
                    depth: modelSize.depth,
                    sourceModelURL: correctedModelURL
                )
                if furniture.serverModelPath == nil,
                   let token = AuthTokenStore.shared.accessToken,
                   !token.hasPrefix("mock_") {
                    saveNotice = "서버 저장 경로가 아직 준비되지 않아 이 기기의 내 가구에 저장했어요."
                }
                isSaving = false
                saved = true
                Haptics.success()
                try? await Task.sleep(for: .milliseconds(saveNotice == nil ? 450 : 900))
                onFurnitureSaved()
            } catch {
                isSaving = false
                alertMessage = error.localizedDescription
                Haptics.error()
            }
        }
    }

    private func makeCorrectedModelURL() throws -> URL? {
        guard let importedModelURL else { return nil }
        let accessed = importedModelURL.startAccessingSecurityScopedResource()
        defer { if accessed { importedModelURL.stopAccessingSecurityScopedResource() } }
        let source = try Data(contentsOf: importedModelURL)
        let corrected = try GLBTransformBaker.bake(data: source, transform: modelTransform)
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Spatium/CorrectedModels", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("SpatiumCorrectedModels", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = importedModelURL.deletingPathExtension().lastPathComponent
        let destination = directory
            .appendingPathComponent(baseName.isEmpty ? UUID().uuidString : "\(baseName)-corrected")
            .appendingPathExtension("glb")
        try corrected.write(to: destination, options: .atomic)
        return destination
    }

    private func resetWizard() {
        imagePreparationTask?.cancel()
        imagePreparationTask = nil
        imagePreparationID = nil
        isPreparingImage = false
        imageRestorationID = nil
        isRestoringImages = false
        step = .upload
        photoItem = nil
        image = nil
        uploadImage = nil
        objectName = ""
        normalizedName = nil
        segmentationReady = false
        isSegmenting = false
        segmentedImage = nil
        segmentedPNG = nil
        segmentationResult = nil
        segmentationError = nil
        showOriginal = false
        generationProgress = 0
        generated = false
        isGenerating = false
        generationError = nil
        segmentationProvider = .groundedSAM2
        generationProvider = .localTripoSR
        mcResolution = 256
        textureResolution = 1024
        remesh = .none
        importedModelURL = nil
        importedModelName = nil
        modelTransform = .initial
        floorSnap = false
        activeTransformAxis = .free
        cameraPreset = .perspective
        autoCorrectionApplied = false
        undoHistory = []
        redoHistory = []
        cameraResetToken = 0
        autoAlignToken = 0
        saveName = ""
        category = initialCategory
        saved = false
        saveNotice = nil
    }
}
