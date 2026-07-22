import SwiftUI

enum ScanEditorPreparationState: Equatable {
    case idle
    case preparing
    case failed(message: String)

    var isPreparing: Bool {
        self == .preparing
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum ScanEditorPreparationOutcome: Equatable {
    case ready(URL)
    case failed(message: String)
    case cancelled
}

enum ScanEditorPreparation {
    static let failureMessage = "스캔 파일을 만들 수 없어요. 저장 공간을 확인한 후 다시 시도해 주세요."

    static func run(_ operation: () async throws -> URL) async -> ScanEditorPreparationOutcome {
        do {
            let url = try await operation()
            try Task.checkCancellation()
            return .ready(url)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(message: failureMessage)
        }
    }
}

private struct ScanEditorPresentation: Identifiable {
    let id = UUID()
    let usdzURL: URL
    let scanItems: [EditableScanItem]
    let roomName: String
    let area: Double
    let ceilingHeight: Double
}

struct EmptyScanView: View {
    var onStartScan: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            EmptyStateCard(
                systemImage: "camera.metering.center.weighted",
                title: "검토할 스캔이 없습니다",
                message: "새 방을 스캔하면 RoomPlan 결과를 확인하고 파일로 내보낼 수 있습니다."
            )

            ActionCTAButton(
                title: "방 스캔 시작",
                subtitle: "방마다 새 스캔을 시작해 정확한 3D 도면을 만드세요",
                systemImage: "camera.viewfinder",
                tint: SpatiumTheme.accent,
                action: onStartScan
            )
        }
    }
}

struct ScanReviewView: View {
    @Binding var project: ScanProject
    /// 3D 에디터에서 저장 시 자동 업로드에 쓰는 소속 프로젝트 정보.
    var projectID: String? = nil
    var projectName: String? = nil
    var exporting: Bool
    var uploading: Bool
    var exportError: String?
    var uploadMessage: String?
    var isGuestMode: Bool = false
    var onStartScan: () -> Void
    var onExport: () -> Void
    var onUpload: () -> Void
    var onOpenSettings: () -> Void
    /// 3D 에디터가 저장 과정에서 서버 룸을 새로 만들었을 때 바깥 상태(activeRoomID 등)를 갱신하는 콜백.
    var onRoomUploaded: ((RoomRecord) -> Void)? = nil
    /// 테스트에서 성공/실패를 결정적으로 재현할 수 있도록 export 동작만 주입 가능하게 둔다.
    var editorUSDZExporter: (ScanProject) async throws -> URL = { project in
        try await project.exportUSDZForEditing()
    }

    @State private var editorPreparationState: ScanEditorPreparationState = .idle
    @State private var editorPreparationTask: Task<Void, Never>?
    /// URL과 편집 스냅샷이 함께 준비된 경우에만 전체 화면 편집기를 표시한다.
    @State private var editorPresentation: ScanEditorPresentation?
    @State private var showsEditorSaveReminder = false
    @State private var shouldPrepareEditorAfterReminder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScanStatusHeader(project: project, onStartScan: onStartScan)
            RoomTypeCard(project: $project)
            ScanEditEntryCard(
                itemCount: project.items.count,
                isGuestMode: isGuestMode,
                preparationState: editorPreparationState,
                onOpen: { showsEditorSaveReminder = true }
            )
            DetectedItemsCard(items: $project.items)
            ExportCard(
                exporting: exporting,
                uploading: uploading,
                exportError: exportError,
                uploadMessage: uploadMessage,
                isGuestMode: isGuestMode,
                onExport: onExport,
                onUpload: onUpload,
                onOpenSettings: onOpenSettings
            )
        }
        .fullScreenCover(item: $editorPresentation) { presentation in
            RoomEditorView(
                scanItems: presentation.scanItems,
                roomName: presentation.roomName,
                usdzURL: presentation.usdzURL,
                area: presentation.area,
                ceilingHeight: presentation.ceilingHeight,
                projectID: projectID,
                projectName: projectName,
                onRoomCreated: onRoomUploaded
            )
        }
        .sheet(
            isPresented: $showsEditorSaveReminder,
            onDismiss: prepareEditorAfterReminderIfNeeded
        ) {
            ScanEditorSaveReminderSheet(isGuestMode: isGuestMode) {
                shouldPrepareEditorAfterReminder = true
            }
        }
        .onChange(of: project.createdAt) { _, _ in
            cancelEditorPreparation()
        }
        .onDisappear {
            // 전체 화면 편집기 표시로 부모가 가려지는 경우에는 준비된 presentation을 유지한다.
            guard editorPresentation == nil else { return }
            editorPreparationTask?.cancel()
            editorPreparationTask = nil
            editorPreparationState = .idle
        }
    }

    private func prepareScanEditor() {
        guard !editorPreparationState.isPreparing else { return }

        editorPreparationTask?.cancel()
        editorPreparationState = .preparing
        let snapshot = project

        editorPreparationTask = Task {
            let outcome = await ScanEditorPreparation.run {
                try await editorUSDZExporter(snapshot)
            }
            guard !Task.isCancelled else { return }

            switch outcome {
            case let .ready(url):
                let footprint = snapshot.estimatedFootprint
                editorPreparationState = .idle
                editorPresentation = ScanEditorPresentation(
                    usdzURL: url,
                    scanItems: snapshot.items,
                    roomName: snapshot.resolvedRoomType,
                    area: footprint.width * footprint.depth,
                    ceilingHeight: snapshot.estimatedCeilingHeight
                )
            case let .failed(message):
                Haptics.error()
                editorPreparationState = .failed(message: message)
            case .cancelled:
                editorPreparationState = .idle
            }
            editorPreparationTask = nil
        }
    }

    private func prepareEditorAfterReminderIfNeeded() {
        guard shouldPrepareEditorAfterReminder else { return }
        shouldPrepareEditorAfterReminder = false
        prepareScanEditor()
    }

    private func cancelEditorPreparation() {
        showsEditorSaveReminder = false
        shouldPrepareEditorAfterReminder = false
        editorPreparationTask?.cancel()
        editorPreparationTask = nil
        editorPreparationState = .idle
        editorPresentation = nil
    }
}

struct ScanEditorSaveReminderSheet: View {
    let isGuestMode: Bool
    var onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var needsExpandedSheet: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: isGuestMode ? "person.crop.circle.badge.exclamationmark" : "square.and.arrow.down.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(isGuestMode ? SpatiumTheme.coral : SpatiumTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(
                            (isGuestMode ? SpatiumTheme.coral : SpatiumTheme.accent).opacity(0.11),
                            in: Circle()
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(isGuestMode ? "웹에서 보려면 로그인이 필요해요" : "3D 공간에서 꼭 저장해 주세요")
                            .font(.headline.weight(.black))
                            .foregroundStyle(SpatiumTheme.text)
                        Text(reminderMessage)
                            .font(.subheadline)
                            .foregroundStyle(SpatiumTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Label(reminderLabel, systemImage: isGuestMode ? "person.crop.circle.badge.checkmark" : "icloud.and.arrow.up.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isGuestMode ? SpatiumTheme.coral : SpatiumTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (isGuestMode ? SpatiumTheme.coral : SpatiumTheme.accent).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                    )

                HStack(spacing: 8) {
                    Button("돌아가기") { dismiss() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SpatiumTheme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(SpatiumTheme.warmPanel)
                        .overlay(
                            RoundedRectangle(cornerRadius: SpatiumRadius.md)
                                .stroke(SpatiumTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                        .buttonStyle(.pressable)

                    Button {
                        onContinue()
                        dismiss()
                    } label: {
                        Label("3D 공간 열기", systemImage: "cube.transparent")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(SpatiumTheme.onCta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(SpatiumTheme.ctaFill)
                            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("scan-editor-reminder-continue")
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SpatiumTheme.background.ignoresSafeArea())
        .presentationDetents(needsExpandedSheet ? [.large] : [.height(isGuestMode ? 260 : 240)])
        .presentationDragIndicator(.visible)
        .presentationBackground(SpatiumTheme.background)
        .accessibilityIdentifier("scan-editor-save-reminder")
    }

    private var reminderMessage: String {
        if isGuestMode {
            return "게스트 모드에서는 3D 공간을 서버에 저장할 수 없어요. 로그인 후 저장하면 웹에서도 확인할 수 있어요."
        }
        return "편집 화면 하단의 ‘저장하기’를 눌러야 스캔 결과와 편집 내용이 서버에 저장되고 웹에서도 확인할 수 있어요."
    }

    private var reminderLabel: String {
        isGuestMode
            ? "로그인한 프로젝트만 웹과 동기화돼요"
            : "‘저장하기’를 눌러야 웹에 반영돼요"
    }
}

/// 스캔 결과를 실제 3D로 열어 객체를 편집하는 진입 카드.
private struct ScanEditEntryCard: View {
    let itemCount: Int
    let isGuestMode: Bool
    let preparationState: ScanEditorPreparationState
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                entryIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(preparationState.isFailed ? SpatiumTheme.coral : SpatiumTheme.text)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                trailingStatus
            }
            .padding(16)
            .background(SpatiumTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.lg)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
            .shadow(color: SpatiumTheme.shadow.opacity(0.12), radius: 14, y: 6)
        }
        .buttonStyle(.pressable)
        .disabled(preparationState.isPreparing)
        .accessibilityHint(entryAccessibilityHint)
        .animation(.easeOut(duration: 0.2), value: preparationState)
    }

    @ViewBuilder
    private var entryIcon: some View {
        ZStack {
            LinearGradient(
                colors: iconGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if preparationState.isPreparing {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: preparationState.isFailed ? "exclamationmark.triangle.fill" : "cube.transparent")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }

    @ViewBuilder
    private var trailingStatus: some View {
        switch preparationState {
        case .idle:
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
        case .preparing:
            Text("준비 중")
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.soft)
        case .failed:
            Label("다시 시도", systemImage: "arrow.clockwise")
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.coral)
        }
    }

    private var title: String {
        switch preparationState {
        case .idle: "3D로 편집하기"
        case .preparing: "3D 편집기 준비 중"
        case .failed: "3D 편집기를 열지 못했어요"
        }
    }

    private var message: String {
        switch preparationState {
        case .idle:
            isGuestMode
                ? "객체 \(itemCount)개를 편집할 수 있어요 · 게스트 공간은 이 기기에만 보관돼요"
                : "객체 \(itemCount)개를 편집한 뒤 저장하면 웹에서도 확인할 수 있어요"
        case .preparing:
            "스캔 메시를 만드는 동안 잠시 기다려 주세요"
        case let .failed(message):
            message
        }
    }

    private var entryAccessibilityHint: String {
        if preparationState.isFailed {
            return "스캔 파일 준비를 다시 시도합니다"
        }
        return isGuestMode
            ? "게스트 보관 안내를 확인한 뒤 스캔된 방을 3D 편집기로 엽니다"
            : "저장 안내를 확인한 뒤 스캔된 방을 3D 편집기로 엽니다"
    }

    private var iconGradient: [Color] {
        preparationState.isFailed
            ? [SpatiumTheme.coral.opacity(0.7), SpatiumTheme.coral]
            : [SpatiumTheme.accentLight, SpatiumTheme.accent]
    }

    private var borderColor: Color {
        preparationState.isFailed
            ? SpatiumTheme.coral.opacity(0.45)
            : SpatiumTheme.accentLight.opacity(0.5)
    }
}

private struct ScanStatusHeader: View {
    let project: ScanProject
    var onStartScan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.resolvedRoomType)
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Text("\(project.items.count)개 요소")
                    .font(.subheadline)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()

            Button(action: onStartScan) {
                Image(systemName: "arrow.clockwise")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(SpatiumTheme.accent.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("다시 스캔")
        }
        .padding(.horizontal, 2)
    }
}

private struct RoomTypeCard: View {
    @Binding var project: ScanProject

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("방 정보")
                    .font(.headline)
                    .foregroundStyle(SpatiumTheme.text)

                TextField("예: 침실, 거실, 주방, 서재", text: $project.roomType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(SpatiumTheme.elevatedSurface)
                    .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.sm).stroke(SpatiumTheme.border, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))

                Text("입력한 값은 metadata JSON 파일의 roomType으로 함께 전송됩니다.")
                    .font(.footnote)
                    .foregroundStyle(SpatiumTheme.soft)
            }
        }
    }
}

struct DetectedItemsCard: View {
    @Binding var items: [EditableScanItem]
    @State private var showsAllItems = false

    private static let previewCount = 3

    private var visibleItemIndices: Range<Int> {
        0..<(showsAllItems ? items.count : min(items.count, Self.previewCount))
    }

    private var hiddenItemCount: Int {
        max(items.count - Self.previewCount, 0)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("감지된 공간 요소")
                        .font(.headline)
                        .foregroundStyle(SpatiumTheme.text)

                    Text("\(items.count)개")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SpatiumTheme.accent.opacity(0.09), in: Capsule())
                }

                if items.isEmpty {
                    ContentUnavailableView("감지된 항목 없음", systemImage: "cube.transparent", description: Text("스캔을 다시 시도해 주세요."))
                        .frame(minHeight: 180)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleItemIndices, id: \.self) { index in
                            EditableScanItemRow(item: $items[index])
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    if hiddenItemCount > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showsAllItems.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(showsAllItems ? "접기" : "\(hiddenItemCount)개 더 보기")
                                    .font(.subheadline.weight(.bold))

                                Spacer()

                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.black))
                                    .rotationEffect(.degrees(showsAllItems ? 180 : 0))
                            }
                            .foregroundStyle(SpatiumTheme.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(SpatiumTheme.accent.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                                    .stroke(SpatiumTheme.accent.opacity(0.15), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                        .accessibilityHint(showsAllItems ? "추가 감지 요소를 숨깁니다" : "나머지 감지 요소를 펼쳐 봅니다")
                        .accessibilityIdentifier("detected-items-toggle")
                    }
                }
            }
        }
        .onChange(of: items.map(\.id)) { _, _ in
            showsAllItems = false
        }
    }
}

private struct ExportCard: View {
    var exporting: Bool
    var uploading: Bool
    var exportError: String?
    var uploadMessage: String?
    var isGuestMode: Bool
    var onExport: () -> Void
    var onUpload: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("출력")
                            .font(.headline.weight(.black))
                            .foregroundStyle(SpatiumTheme.text)
                        // 내부 서버 주소를 그대로 노출하지 않고 동작 설명만 보여준다.
                        Text("스캔 파일을 공유하거나 프로젝트에 저장합니다")
                            .font(.caption)
                            .foregroundStyle(SpatiumTheme.soft)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: onOpenSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SpatiumTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(SpatiumTheme.accent.opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("서버 설정")
                }

                OutputActionButton(
                    title: exporting ? "준비 중" : "파일 공유 (USDZ + JSON)",
                    systemImage: "square.and.arrow.up",
                    tint: SpatiumTheme.sage,
                    action: onExport
                )
                .disabled(exporting || uploading)

                if isGuestMode {
                    Label(
                        "게스트 모드에서는 서버 업로드를 사용할 수 없어요. 로그인 후 이용해 주세요.",
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("guest-scan-upload-restriction")
                }

                Button(action: onUpload) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.doc")
                            .font(.headline.weight(.bold))
                        Text(uploading ? "업로드 중..." : isGuestMode ? "로그인 후 서버 업로드" : "서버로 업로드")
                            .font(.headline.weight(.bold))
                        Spacer()
                        if uploading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.subheadline.weight(.black))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .background(SpatiumTheme.ctaFill)
                    .foregroundStyle(SpatiumTheme.onCta)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(exporting || uploading)

                if let exportError {
                    Text(exportError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let uploadMessage {
                    Text(uploadMessage)
                        .font(.footnote)
                        .foregroundStyle(uploadMessage.hasPrefix("업로드 실패") ? .red : SpatiumTheme.muted)
                }
            }
        }
    }
}

private struct OutputActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                Text(title)
                    .font(.subheadline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.11))
            .foregroundStyle(tint)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(tint.opacity(0.18), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

private struct EditableScanItemRow: View {
    @Binding var item: EditableScanItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.iconName)
                .font(.title3)
                .frame(width: 34, height: 34)
                .foregroundStyle(SpatiumTheme.accent)
                .background(SpatiumTheme.warmPanel)
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)

                Text(item.measurementSummary)
                    .font(.caption)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()
        }
        .padding(12)
        .background(SpatiumTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }
}
