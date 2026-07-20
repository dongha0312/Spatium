import SwiftUI

/// 3D 모델링 에디터 페이지. 프런트엔드 `3dEditor.js`의 화면 구성을 그대로 옮겼습니다.
/// 상단 내비 + 툴바, 좌측(폰=상단) 가구 카탈로그 패널, 3D 캔버스 + 하단 뷰바,
/// 하단 액션바(취소/미리보기/저장), 선택 시 치수·회전·교체·제거 컨트롤.
struct RoomEditorView: View {
    @StateObject var viewModel: RoomEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userFurnitureStore: UserFurnitureStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// 같은 프로젝트의 다른 방들. 2개 이상이면 툴바의 방 이름이 드롭다운으로 바뀝니다.
    private let availableRooms: [RoomRecord]
    private let onSelectRoom: ((RoomRecord) -> Void)?

    @State var showReplacePanel = false
    @State var showCatalog = false
    /// 카탈로그의 "사용자 가구" 카테고리에서 여는 사진→3D 가구 만들기 화면.
    @State var showImgTo3D = false
    /// 책장 꾸미기 패널(소품 없음)에서 여는 가구 만들기 화면.
    /// 카탈로그 시트용과 상태를 분리해야 시트가 닫힌 상태에서도 띄울 수 있다.
    @State var showImgTo3DFromDecor = false
    /// 저장 안 된 변경이 있을 때 방 전환 확인용으로 보관해 두는 대상 방.
    @State private var pendingRoomSwitch: RoomRecord?
    @State var activeGroup: String? = nil
    @State var catalogSearch = ""
    @FocusState var catalogSearchFocused: Bool
    @State var placementNotice: String?
    @State var placementNoticeTask: Task<Void, Never>?
    /// 벽/바닥 중 하나만 열리는 단일 플로팅 팔레트. 툴바 자체의 높이는 항상 고정한다.
    @State var activeSurfaceColorPicker: SurfaceColorPicker?
    @State var showViewHelp = false
    /// 로컬 복구본 저장에 실패한 상태에서 에디터를 닫아 작업이 사라지는 것을 방지한다.
    @State private var showDraftSaveExitWarning = false

    init(
        room: RoomRecord,
        projectID: String? = nil,
        projectName: String? = nil,
        availableRooms: [RoomRecord] = [],
        onSelectRoom: ((RoomRecord) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: RoomEditorViewModel(room: room, projectID: projectID, projectName: projectName))
        self.availableRooms = availableRooms
        self.onSelectRoom = onSelectRoom
    }

    /// 스캔 결과 또는 서버 저장 룸을 여는 3D 에디터: 방 메시 위에서 감지/편집된 가구를 편집합니다.
    /// roomID/projectID가 있으면(서버 룸) 편집 후 서버에 저장할 수 있습니다.
    /// onRoomCreated: 저장 과정에서 새 서버 룸이 만들어졌을 때(스캔 첫 업로드) 호출됩니다.
    init(
        scanItems: [EditableScanItem],
        roomName: String,
        usdzURL: URL?,
        initialFloorColor: String? = nil,
        area: Double,
        ceilingHeight: Double,
        roomID: String? = nil,
        projectID: String? = nil,
        projectName: String? = nil,
        availableRooms: [RoomRecord] = [],
        onSelectRoom: ((RoomRecord) -> Void)? = nil,
        onRoomCreated: ((RoomRecord) -> Void)? = nil
    ) {
        let model = RoomEditorViewModel(
            scanItems: scanItems,
            roomName: roomName,
            usdzURL: usdzURL,
            initialFloorColor: initialFloorColor,
            area: area,
            ceilingHeight: ceilingHeight,
            roomID: roomID,
            projectID: projectID,
            projectName: projectName
        )
        model.onServerRoomCreated = onRoomCreated
        _viewModel = StateObject(wrappedValue: model)
        self.availableRooms = availableRooms
        self.onSelectRoom = onSelectRoom
    }

    /// 가로모드에서는 화면 높이가 짧아 접근성 최대 글씨를 그대로 적용하면 상·하단 고정 바와
    /// 3D 캔버스를 함께 사용할 수 없다. 세로모드는 전체 범위를 유지하고 가로만 XXXL로 제한한다.
    private var editorDynamicTypeRange: ClosedRange<DynamicTypeSize> {
        .xSmall...(verticalSizeClass == .compact ? .xxxLarge : .accessibility5)
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
                .zIndex(2)
            toolbar
                .zIndex(2)
            canvas
                .zIndex(0)
            // 가구 추가 시트가 떠 있는 동안엔 어두운 하단 바가 시트 모서리 밖으로 비치므로 숨긴다.
            if !showCatalog {
                EditorFooterView(
                    hasUnsavedChanges: viewModel.hasUnsavedChanges,
                    draftSaveState: viewModel.draftSaveState,
                    isGuestLocalProject: viewModel.isGuestLocalProject,
                    isOffline: viewModel.isOffline,
                    isSaving: viewModel.isSaving,
                    onDiscard: discardAndClose,
                    onSave: saveEditor,
                    onRetryDraftSave: {
                        Task { await viewModel.retryDraftSave() }
                    }
                )
            }
        }
        .background(
            (showCatalog ? SpatiumTheme.surface : SpatiumTheme.editorPanel)
                .ignoresSafeArea()
        )
        .dynamicTypeSize(editorDynamicTypeRange)
        .animation(.easeOut(duration: 0.2), value: showCatalog)
        .task { await viewModel.loadLayout() }
        .onDisappear {
            placementNoticeTask?.cancel()
            Task { await viewModel.persistDraftImmediately() }
        }
        .onChange(of: viewModel.viewMode) { _, viewMode in
            if viewMode == .person {
                showCatalog = false
            }
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-UITestCatalog") {
                showCatalog = true
            }
            // 스크린샷 검증용: 카탈로그를 "사용자 가구" 카테고리로 연다.
            if ProcessInfo.processInfo.arguments.contains("-UITestCatalogUserGroup") {
                activeGroup = FurnitureCatalog.userFurnitureFilterID
                showCatalog = true
            }
            if ProcessInfo.processInfo.arguments.contains("-UITestViewHelp") {
                showViewHelp = true
            }
            // 선택 카드 검증용: 카탈로그 의자를 놓아 선택 상태(회전·높이·크기 컨트롤)를 연다.
            if ProcessInfo.processInfo.arguments.contains("-UITestSelectFurniture") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    if let chair = userFurnitureStore.catalogItems.first(where: { $0.id == "modern_chair" }) {
                        viewModel.place(catalogItem: chair)
                    }
                }
            }
            // 꾸미기 검증용: 책장을 놓고 꾸미기 모드로 들어간다. QuickPlacement 플래그는
            // 프런트와 같은 "소품 선택 → 선반 직접 탭" 대기 상태를 만든다.
            let testsPlacedDecor = ProcessInfo.processInfo.arguments.contains("-UITestDecor")
            let testsQuickDecorPlacement = ProcessInfo.processInfo.arguments.contains("-UITestDecorQuickPlacement")
            if testsPlacedDecor || testsQuickDecorPlacement {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    guard let bookcase = userFurnitureStore.catalogItems
                        .first(where: { $0.modelFileName == "editable_bookcase" }) else { return }
                    viewModel.place(catalogItem: bookcase)
                    viewModel.isMovingSelectedFurniture = false
                    viewModel.setSelectedRotation(degrees: 180)
                    try? await Task.sleep(for: .milliseconds(900))
                    viewModel.beginDecorating()
                    try? await Task.sleep(for: .milliseconds(900))
                    if let model = userFurnitureStore.catalogItems.first(where: { $0.id == "modern_chair" }) {
                        let figure = FurnitureCatalogItem(
                            id: "ui_test_figure",
                            name: "모던 피규어",
                            group: "피규어",
                            category: "figure",
                            width: model.width,
                            height: model.height,
                            depth: model.depth,
                            modelFileName: model.modelFileName
                        )
                        viewModel.prepareDecorPlacement(figure)
                        if testsPlacedDecor {
                            viewModel.placePendingFigure(atLocal: .init(x: 0.15, y: 1.8, z: 0))
                            viewModel.selectedDecorID = nil
                        }
                    }
                }
            }
        }
        #endif
        .sheet(isPresented: $showViewHelp) {
            EditorViewHelpSheet(currentMode: viewModel.viewMode)
        }
        .fullScreenCover(isPresented: $showImgTo3DFromDecor) {
            imgTo3DCover(isPresented: $showImgTo3DFromDecor, initialCategory: .figure)
        }
        .sheet(isPresented: $showCatalog) {
            catalogSheet
        }
        .sheet(isPresented: $showReplacePanel) {
            FurniturePanelView(title: "가구 교체") { furniture in
                viewModel.replaceSelected(with: furniture)
            }
        }
        .sheet(item: $pendingRoomSwitch) { room in
            ConfirmSheet(
                title: "저장하지 않은 변경이 있어요",
                message: "'\(room.roomType)' 방으로 이동하면 지금 방의 저장하지 않은 편집 내용이 사라집니다.",
                confirmTitle: "이동하기",
                confirmSystemImage: "arrow.right",
                onConfirm: {
                    Task {
                        await viewModel.discardCurrentDraft()
                        onSelectRoom?(room)
                    }
                }
            )
        }
        .alert(
            "임시 저장된 편집을 복구할까요?",
            isPresented: Binding(
                get: { viewModel.hasRecoverableDraft },
                set: { isPresented in
                    if !isPresented, viewModel.hasRecoverableDraft {
                        Task { await viewModel.discardRecoverableDraft() }
                    }
                }
            )
        ) {
            Button("복구하기") {
                viewModel.restoreRecoverableDraft()
            }
            Button("새로 시작", role: .destructive) {
                Task { await viewModel.discardRecoverableDraft() }
            }
        } message: {
            Text("이 기기에 자동으로 저장된 편집 내용이 있습니다. 복구하면 마지막 작업 상태부터 이어갈 수 있어요.")
        }
        .alert("임시 저장에 실패했어요", isPresented: $showDraftSaveExitWarning) {
            Button("다시 시도") {
                Haptics.selection()
                Task {
                    await viewModel.retryDraftSave()
                    if viewModel.draftSaveState.failureMessage == nil {
                        dismiss()
                    }
                }
            }
            Button("저장하지 않고 나가기", role: .destructive) {
                Task {
                    await viewModel.discardCurrentDraft()
                    dismiss()
                }
            }
            Button("계속 편집", role: .cancel) {}
        } message: {
            Text(viewModel.draftSaveState.failureMessage ?? RoomEditorViewModel.draftSaveFailureMessage)
        }
    }

    // MARK: - 상단 내비게이션

    private var navBar: some View {
        HStack(spacing: 0) {
            Button {
                closeEditor()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("에디터 닫기")

            // 오른쪽 히스토리 버튼 두 개와 폭을 맞춰 브랜드가 정확히 화면 중앙에 오게 한다.
            Color.clear
                .frame(width: 44, height: 1)
                .allowsHitTesting(false)

            Spacer(minLength: 6)

            HStack(spacing: 7) {
                BrandMark(size: 18)
                Text("SPATIUM")
                    .font(.caption.weight(.black))
                    .tracking(4)
                    .foregroundStyle(SpatiumTheme.text)
            }

            Spacer(minLength: 6)

            HStack(spacing: 0) {
                historyButton(
                    systemImage: "arrow.uturn.backward",
                    accessibilityLabel: "실행 취소",
                    isEnabled: viewModel.canUndo,
                    action: {
                        Task { await viewModel.undo() }
                    }
                )
                historyButton(
                    systemImage: "arrow.uturn.forward",
                    accessibilityLabel: "다시 실행",
                    isEnabled: viewModel.canRedo,
                    action: {
                        Task { await viewModel.redo() }
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(SpatiumTheme.surface)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [SpatiumTheme.border.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 6)
        }
    }

    private func closeEditor() {
        Task {
            // 화면이 사라진 뒤가 아니라 닫기 전에 쓰기를 완료해야 실패 안내를 보여줄 수 있다.
            await viewModel.persistDraftImmediately()
            if viewModel.hasUnsavedChanges, viewModel.draftSaveState.failureMessage != nil {
                showDraftSaveExitWarning = true
            } else {
                dismiss()
            }
        }
    }

    private func discardAndClose() {
        Task {
            await viewModel.discardCurrentDraft()
            dismiss()
        }
    }

    private func saveEditor() {
        Task { await viewModel.save() }
    }

    private func historyButton(
        systemImage: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(isEnabled ? SpatiumTheme.accent : SpatiumTheme.soft.opacity(0.35))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityLabel == "실행 취소" ? "editor-undo-button" : "editor-redo-button")
    }

    // MARK: - 툴바

    /// 저장 상태 색: 서버 저장 가능 초록 / 로컬 전용 주황. 네트워크 상태가 아니라
    /// "이 방의 편집이 서버에 저장되는지"를 나타낸다. (어두운 툴바 위에서 잘 보이는 톤)
    private var connectionColor: Color {
        viewModel.isOffline
            ? Color(red: 0.96, green: 0.68, blue: 0.32)
            : Color(red: 0.40, green: 0.80, blue: 0.46)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            // 프로젝트 이름 · 방 이름 — 프로젝트에 방이 여러 개면 드롭다운으로 방을 전환할 수 있다.
            if let onSelectRoom, availableRooms.count > 1 {
                Menu {
                    ForEach(availableRooms) { room in
                        Button {
                            if viewModel.hasUnsavedChanges {
                                pendingRoomSwitch = room
                            } else {
                                onSelectRoom(room)
                            }
                        } label: {
                            if room.id == viewModel.roomID {
                                Label(room.roomType, systemImage: "checkmark")
                            } else {
                                Text(room.roomType)
                            }
                        }
                    }
                } label: {
                    roomChipLabel(showsChevron: true)
                }
            } else {
                roomChipLabel(showsChevron: false)
            }

            connectionBadge

            Spacer()

            // 꾸미기 모드에서는 방 가구 추가 대신 피규어 패널이 카탈로그 역할을 한다.
            if !viewModel.isDecorating && !viewModel.isPersonView {
                Button {
                    viewModel.selectedItemID = nil
                    viewModel.isMovingSelectedFurniture = false
                    showCatalog = true
                } label: {
                    Label("가구 추가", systemImage: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(SpatiumTheme.accent, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            LinearGradient(
                colors: [
                    SpatiumTheme.editorToolbar,
                    SpatiumTheme.editorToolbar.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    /// 프로젝트 이름 · 방 이름 칩. 드롭다운일 때는 화살표를 함께 보여준다.
    private func roomChipLabel(showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            if let projectName = viewModel.projectName {
                Text(projectName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text("·")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Text(viewModel.layout.roomName)
                .font(.caption2)
                .foregroundStyle(.white.opacity(viewModel.projectName == nil ? 0.85 : 0.55))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// 저장 상태 배지. "오프라인"은 네트워크가 멀쩡해도 뜰 수 있어(방 데이터 미로드,
    /// 게스트/로컬 룸) 오해를 부르므로 "로컬 편집"으로 표기한다.
    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
            Text(viewModel.isOffline ? "로컬 편집" : "온라인")
                .font(.caption2.weight(.bold))
                .foregroundStyle(connectionColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(connectionColor.opacity(0.13))
        .clipShape(Capsule())
    }

}
