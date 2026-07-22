import SwiftUI
import UniformTypeIdentifiers

struct RoomAddFlowSheet: View {
    let projectName: String
    let canUploadFiles: Bool
    var onChooseScan: () -> Void
    var onRequestLogin: () -> Void
    var onUpload: (_ roomName: String, _ jsonURL: URL, _ usdzURL: URL) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .method

    private enum Step {
        case method
        case fileUpload
    }

    var body: some View {
        Group {
            switch step {
            case .method:
                methodSelection
            case .fileUpload:
                RoomFileUploadForm(
                    projectName: projectName,
                    onBack: { withAnimation(.snappy) { step = .method } },
                    onUpload: onUpload
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SpatiumTheme.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SpatiumTheme.background)
    }

    private var methodSelection: some View {
        VStack(spacing: 0) {
            RoomAddSheetHeader(
                title: "방 추가하기",
                subtitle: projectName,
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("어떤 방식으로 공간을 가져올까요?")
                        .font(.title3.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)

                    Text("새로 스캔하거나, 이미 만들어 둔 RoomPlan 파일을 그대로 업로드할 수 있어요.")
                        .font(.subheadline)
                        .lineSpacing(3)
                        .foregroundStyle(SpatiumTheme.soft)
                        .fixedSize(horizontal: false, vertical: true)

                    RoomAddMethodButton(
                        title: "카메라로 새로 스캔",
                        subtitle: "LiDAR로 지금 있는 방을 직접 스캔해요",
                        systemImage: "camera.viewfinder",
                        accessibilityIdentifier: "room-add-scan-option"
                    ) {
                        onChooseScan()
                    }

                    RoomAddMethodButton(
                        title: "USDZ와 JSON 가져오기",
                        subtitle: canUploadFiles
                            ? "기존 3D 모델과 metadata를 서버에 저장해요"
                            : "로그인하면 기존 파일을 서버에 저장할 수 있어요",
                        systemImage: "square.and.arrow.up.on.square",
                        accessibilityIdentifier: "room-add-file-option"
                    ) {
                        if canUploadFiles {
                            withAnimation(.snappy) { step = .fileUpload }
                        } else {
                            onRequestLogin()
                        }
                    }

                    Label(
                        "USDZ는 최대 100MB, JSON은 최대 10MB까지 선택할 수 있어요.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(SpatiumTheme.soft)
                    .padding(.top, 2)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct RoomFileUploadForm: View {
    let projectName: String
    var onBack: () -> Void
    var onUpload: (_ roomName: String, _ jsonURL: URL, _ usdzURL: URL) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var jsonFile: PreparedUploadFile?
    @State private var usdzFile: PreparedUploadFile?
    @State private var preparingKind: UploadFileKind?
    @State private var showJSONImporter = false
    @State private var showUSDZImporter = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var preparationTask: Task<Void, Never>?
    @FocusState private var roomNameFocused: Bool

    private var trimmedRoomName: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canUpload: Bool {
        !trimmedRoomName.isEmpty && jsonFile != nil && usdzFile != nil && preparingKind == nil && !isUploading
    }

    var body: some View {
        VStack(spacing: 0) {
            RoomAddSheetHeader(
                title: "파일로 방 추가",
                subtitle: projectName,
                onBack: onBack,
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    roomNameField

                    VStack(alignment: .leading, spacing: 10) {
                        Text("방 파일")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(SpatiumTheme.text)

                        RoomUploadFileButton(
                            title: "3D 공간 모델",
                            expectedFormat: "USDZ · 최대 100MB",
                            systemImage: "cube.transparent",
                            file: usdzFile,
                            isPreparing: preparingKind == .roomUSDZ,
                            accessibilityIdentifier: "room-usdz-file-picker"
                        ) {
                            showUSDZImporter = true
                        }

                        RoomUploadFileButton(
                            title: "공간 metadata",
                            expectedFormat: "JSON · 최대 10MB",
                            systemImage: "curlybraces.square",
                            file: jsonFile,
                            isPreparing: preparingKind == .roomJSON,
                            accessibilityIdentifier: "room-json-file-picker"
                        ) {
                            showJSONImporter = true
                        }
                    }

                    Label(
                        "두 파일은 같은 RoomPlan 내보내기 결과여야 가구 위치와 공간 모델이 정확히 맞아요.",
                        systemImage: "checkmark.seal"
                    )
                    .font(.caption)
                    .lineSpacing(3)
                    .foregroundStyle(SpatiumTheme.soft)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            uploadAction
        }
        .fileImporter(
            isPresented: $showUSDZImporter,
            allowedContentTypes: [UTType(filenameExtension: "usdz") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleSelection(result, kind: .roomUSDZ)
        }
        .fileImporter(
            isPresented: $showJSONImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleSelection(result, kind: .roomJSON)
        }
        .alert("파일을 확인해주세요", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .interactiveDismissDisabled(isUploading)
        .onDisappear {
            preparationTask?.cancel()
            UploadFilePreparation.remove(jsonFile)
            UploadFilePreparation.remove(usdzFile)
        }
    }

    private var roomNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("방 이름")
                .font(.subheadline.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
            TextField("예: 거실, 침실, 작업실", text: $roomName)
                .focused($roomNameFocused)
                .submitLabel(.done)
                .padding(13)
                .background(SpatiumTheme.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: SpatiumRadius.md)
                        .stroke(SpatiumTheme.border, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                .accessibilityIdentifier("room-upload-name-field")
        }
    }

    private var uploadAction: some View {
        VStack(spacing: 0) {
            Divider().overlay(SpatiumTheme.border)
            PrimaryButton(
                title: isUploading ? "방 업로드 중…" : "이 방 추가하기",
                systemImage: "square.and.arrow.up.fill",
                action: uploadRoom
            )
            .disabled(!canUpload)
            .accessibilityIdentifier("room-file-upload-button")
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func handleSelection(
        _ result: Result<[URL], Error>,
        kind: UploadFileKind
    ) {
        switch result {
        case let .success(urls):
            guard let sourceURL = urls.first else { return }
            preparationTask?.cancel()
            preparingKind = kind
            preparationTask = Task {
                var preparedFile: PreparedUploadFile?
                do {
                    preparedFile = try await UploadFilePreparation.prepare(
                        sourceURL: sourceURL,
                        kind: kind
                    )
                    try Task.checkCancellation()
                    guard let preparedFile else { return }
                    switch kind {
                    case .roomJSON:
                        UploadFilePreparation.remove(jsonFile)
                        jsonFile = preparedFile
                    case .roomUSDZ:
                        UploadFilePreparation.remove(usdzFile)
                        usdzFile = preparedFile
                    case .furnitureGLB:
                        break
                    }
                    Haptics.success()
                } catch is CancellationError {
                    UploadFilePreparation.remove(preparedFile)
                } catch {
                    UploadFilePreparation.remove(preparedFile)
                    errorMessage = error.localizedDescription
                    Haptics.error()
                }
                if preparingKind == kind { preparingKind = nil }
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    private func uploadRoom() {
        guard canUpload, let jsonFile, let usdzFile else { return }
        roomNameFocused = false
        isUploading = true
        errorMessage = nil
        Task {
            do {
                try await onUpload(trimmedRoomName, jsonFile.url, usdzFile.url)
                isUploading = false
                Haptics.success()
                dismiss()
            } catch {
                isUploading = false
                errorMessage = error.localizedDescription
                Haptics.error()
            }
        }
    }
}

private struct RoomAddSheetHeader: View {
    let title: String
    let subtitle: String
    var onBack: (() -> Void)?
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(SpatiumTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(SpatiumTheme.warmPanel, in: Circle())
                        .overlay(Circle().stroke(SpatiumTheme.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("추가 방식으로 돌아가기")
            } else {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(SpatiumTheme.accent.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(SpatiumTheme.accent.opacity(0.12), lineWidth: 1))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)

                Label("프로젝트 · \(subtitle)", systemImage: "folder.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SpatiumTheme.accent.opacity(0.08), in: Capsule())
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(SpatiumTheme.muted)
                    .frame(width: 36, height: 36)
                    .background(SpatiumTheme.warmPanel, in: Circle())
                    .overlay(Circle().stroke(SpatiumTheme.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("방 추가 닫기")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(SpatiumTheme.background)
    }
}

private struct RoomAddMethodButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accessibilityIdentifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 50, height: 50)
                    .background(SpatiumTheme.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(SpatiumTheme.accent)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpatiumTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous)
                    .stroke(SpatiumTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct RoomUploadFileButton: View {
    let title: String
    let expectedFormat: String
    let systemImage: String
    let file: PreparedUploadFile?
    let isPreparing: Bool
    let accessibilityIdentifier: String
    var action: () -> Void

    private var fileSize: String? {
        guard let file else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: file.byteCount)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if isPreparing {
                        ProgressView().tint(SpatiumTheme.accent)
                    } else {
                        Image(systemName: file == nil ? systemImage : "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(file == nil ? SpatiumTheme.accent : SpatiumTheme.success)
                    }
                }
                .frame(width: 42, height: 42)
                .background(SpatiumTheme.warmPanel, in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                    Text(file.map { "\($0.originalFileName) · \(fileSize ?? "")" } ?? expectedFormat)
                        .font(.caption)
                        .foregroundStyle(file == nil ? SpatiumTheme.soft : SpatiumTheme.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Text(file == nil ? "선택" : "변경")
                    .font(.caption.weight(.black))
                    .foregroundStyle(SpatiumTheme.accent)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpatiumTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                    .stroke(file == nil ? SpatiumTheme.border : SpatiumTheme.accent.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(isPreparing)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
