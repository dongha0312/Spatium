import SwiftUI
import UIKit

private enum SurfaceColorPicker: Equatable {
    case wall
    case floor

    var title: String {
        switch self {
        case .wall: "벽 색상"
        case .floor: "바닥 색상"
        }
    }

    var systemImage: String {
        switch self {
        case .wall: "paintpalette"
        case .floor: "square.grid.2x2"
        }
    }
}

private enum FurnitureAdjustment: String, CaseIterable, Identifiable {
    case rotation
    case elevation
    case size

    var id: Self { self }

    var title: String {
        switch self {
        case .rotation: "회전"
        case .elevation: "높이"
        case .size: "크기"
        }
    }

    var systemImage: String {
        switch self {
        case .rotation: "rotate.3d"
        case .elevation: "arrow.up.and.down"
        case .size: "arrow.up.left.and.arrow.down.right"
        }
    }
}

private enum DecorNudgeDirection: String, CaseIterable, Identifiable {
    case left
    case right
    case forward
    case backward

    var id: Self { self }

    var title: String {
        switch self {
        case .left: "왼쪽"
        case .right: "오른쪽"
        case .forward: "앞쪽"
        case .backward: "뒤쪽"
        }
    }

    var systemImage: String {
        switch self {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .forward: "arrow.up"
        case .backward: "arrow.down"
        }
    }

    var delta: (x: Double, z: Double) {
        switch self {
        case .left: (-RoomEditorViewModel.decorNudgeStep, 0)
        case .right: (RoomEditorViewModel.decorNudgeStep, 0)
        case .forward: (0, RoomEditorViewModel.decorNudgeStep)
        case .backward: (0, -RoomEditorViewModel.decorNudgeStep)
        }
    }
}

/// 3D 모델링 에디터 페이지. 프런트엔드 `3dEditor.js`의 화면 구성을 그대로 옮겼습니다.
/// 상단 내비 + 툴바, 좌측(폰=상단) 가구 카탈로그 패널, 3D 캔버스 + 하단 뷰바,
/// 하단 액션바(취소/미리보기/저장), 선택 시 치수·회전·교체·제거 컨트롤.
struct RoomEditorView: View {
    @StateObject private var viewModel: RoomEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userFurnitureStore: UserFurnitureStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// 같은 프로젝트의 다른 방들. 2개 이상이면 툴바의 방 이름이 드롭다운으로 바뀝니다.
    private let availableRooms: [RoomRecord]
    private let onSelectRoom: ((RoomRecord) -> Void)?

    @State private var showReplacePanel = false
    @State private var showCatalog = false
    /// 카탈로그의 "사용자 가구" 카테고리에서 여는 사진→3D 가구 만들기 화면.
    @State private var showImgTo3D = false
    /// 책장 꾸미기 패널(소품 없음)에서 여는 가구 만들기 화면.
    /// 카탈로그 시트용과 상태를 분리해야 시트가 닫힌 상태에서도 띄울 수 있다.
    @State private var showImgTo3DFromDecor = false
    /// 저장 안 된 변경이 있을 때 방 전환 확인용으로 보관해 두는 대상 방.
    @State private var pendingRoomSwitch: RoomRecord?
    @State private var activeGroup: String? = nil
    @State private var catalogSearch = ""
    @FocusState private var catalogSearchFocused: Bool
    @State private var placementNotice: String?
    @State private var placementNoticeTask: Task<Void, Never>?
    /// 벽/바닥 중 하나만 열리는 단일 플로팅 팔레트. 툴바 자체의 높이는 항상 고정한다.
    @State private var activeSurfaceColorPicker: SurfaceColorPicker?
    @State private var showViewHelp = false
    /// 문/창문 제거 시 '개구부로 남기기 / 벽으로 메우기' 선택 다이얼로그.
    @State private var showDeleteOptions = false
    /// 선택 카드에서는 한 번에 하나의 조절 슬라이더만 보여 캔버스를 덜 가린다.
    @State private var selectedFurnitureAdjustment: FurnitureAdjustment = .rotation
    /// 프런트엔드의 `isReplacingSelected`에 대응하는 꾸미기 전용 교체 상태.
    @State private var isReplacingDecor = false
    /// 로컬 복구본 저장에 실패한 상태에서 에디터를 닫아 작업이 사라지는 것을 방지한다.
    @State private var showDraftSaveExitWarning = false

    private static let wallColors = ["#F5F0EA", "#E8DCC8", "#C4956A", "#3A3A3A"]
    private static let floorColors = ["#D8C4A0", "#B08968", "#6B4A34", "#C9C9C9"]

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

    private var visibleItems: [FurnitureCatalogItem] {
        let query = catalogSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return userFurnitureStore.catalogItems.filter { item in
            let matchesGroup = FurnitureCatalog.matches(item, groupFilter: activeGroup)
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.group.localizedCaseInsensitiveContains(query)
                || item.category.localizedCaseInsensitiveContains(query)
            return matchesGroup && matchesSearch
        }
    }

    private var catalogGroups: [String] {
        FurnitureCatalog.editorGroups(in: userFurnitureStore.catalogItems)
    }

    /// 카탈로그가 열려 있거나 새 가구의 위치를 잡는 동안에는 하단 UI가 룸을
    /// 가리므로, 두 단계를 하나의 배치 흐름으로 보고 같은 상향 위치를 유지한다.
    private var shouldLiftRoomForFurniturePlacement: Bool {
        showCatalog || viewModel.isMovingSelectedFurniture || viewModel.isDecorating
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
                footer
            }
        }
        .background(
            (showCatalog ? SpatiumTheme.surface : SpatiumTheme.editorPanel)
                .ignoresSafeArea()
        )
        .animation(.easeOut(duration: 0.2), value: showCatalog)
        .task { await viewModel.loadLayout() }
        .onDisappear {
            placementNoticeTask?.cancel()
            viewModel.persistDraftImmediately()
        }
        .onChange(of: viewModel.selectedDecorID) { _, selectedDecorID in
            if selectedDecorID == nil {
                isReplacingDecor = false
            }
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
            ViewHelpSheet(currentMode: viewModel.viewMode)
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
                    viewModel.discardCurrentDraft()
                    onSelectRoom?(room)
                }
            )
        }
        .alert(
            "임시 저장된 편집을 복구할까요?",
            isPresented: Binding(
                get: { viewModel.hasRecoverableDraft },
                set: { isPresented in
                    if !isPresented, viewModel.hasRecoverableDraft {
                        viewModel.discardRecoverableDraft()
                    }
                }
            )
        ) {
            Button("복구하기") {
                viewModel.restoreRecoverableDraft()
            }
            Button("새로 시작", role: .destructive) {
                viewModel.discardRecoverableDraft()
            }
        } message: {
            Text("이 기기에 자동으로 저장된 편집 내용이 있습니다. 복구하면 마지막 작업 상태부터 이어갈 수 있어요.")
        }
        .alert("임시 저장에 실패했어요", isPresented: $showDraftSaveExitWarning) {
            Button("다시 시도") {
                Haptics.selection()
                viewModel.retryDraftSave()
                if viewModel.draftSaveState.failureMessage == nil {
                    dismiss()
                }
            }
            Button("저장하지 않고 나가기", role: .destructive) {
                viewModel.discardCurrentDraft()
                dismiss()
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
                    action: viewModel.undo
                )
                historyButton(
                    systemImage: "arrow.uturn.forward",
                    accessibilityLabel: "다시 실행",
                    isEnabled: viewModel.canRedo,
                    action: viewModel.redo
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
        // 화면이 사라진 뒤가 아니라 닫기 전에 즉시 쓰기를 완료해야 실패 안내를 보여줄 수 있다.
        viewModel.persistDraftImmediately()
        if viewModel.hasUnsavedChanges, viewModel.draftSaveState.failureMessage != nil {
            showDraftSaveExitWarning = true
        } else {
            dismiss()
        }
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

    // MARK: - 좌측(상단) 가구 카탈로그 패널

    /// 가구 카탈로그 — 끌어올리는 하단 시트. medium 높이에선 뒤 캔버스를 그대로 조작할 수 있어
    /// 상품을 담으면 방에 바로 나타나는 걸 보면서 작업할 수 있습니다.
    private var catalogSheet: some View {
        VStack(spacing: 0) {
            zoneHeader
            catalogSearchField
            categoryFilters

            ScrollView {
                LazyVStack(spacing: 8) {
                    // 사용자 가구 카테고리에서는 가구를 새로 만들 수 있는 입구를 함께 보여준다.
                    if activeGroup == FurnitureCatalog.userFurnitureFilterID {
                        createFurnitureCTA
                    }
                    if visibleItems.isEmpty {
                        catalogEmptyState
                    } else {
                        ForEach(visibleItems) { item in
                            CatalogProductRow(item: item) {
                                placeCatalogItem(item)
                            }
                        }
                    }
                }
                // 좌우 18: 위 검색창·칩과 같은 인셋으로 정렬.
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            // 시트 하단에서 카드가 뚝 잘려 보이지 않게 알파 마스크로 페이드아웃.
            // (배경색을 덧씌우는 방식은 진한 버튼만 도드라져 얼룩져 보인다)
            .mask(
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)
                }
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(SpatiumTheme.surface)
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        // 시트 자체 배경(기본 회색 크롬)을 테마 서페이스로 통일해 회색이 비치지 않게.
        .presentationBackground(SpatiumTheme.surface)
        .fullScreenCover(isPresented: $showImgTo3D) {
            imgTo3DCover(isPresented: $showImgTo3D)
        }
    }

    /// 사용자 가구 카테고리 상단의 "사진으로 3D 가구 만들기" 입구 카드.
    private var createFurnitureCTA: some View {
        Button {
            showImgTo3D = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.onCta)
                    .frame(width: 44, height: 44)
                    .background(SpatiumTheme.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("사진으로 3D 가구 만들기")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("가구 사진 한 장으로 나만의 3D 가구를 만들어요")
                        .font(.caption2)
                        .foregroundStyle(SpatiumTheme.soft)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.soft)
            }
            .padding(12)
            .background(SpatiumTheme.warmPanel)
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                    .stroke(SpatiumTheme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("가구 만들기 화면을 엽니다")
    }

    /// 카탈로그·꾸미기 패널에서 여는 가구 만들기(ImgTo3D) 전체 화면. 저장하면
    /// 사용자 가구/소품 목록이 곧바로 갱신된다(UserFurnitureStore 공유).
    private func imgTo3DCover(
        isPresented: Binding<Bool>,
        initialCategory: ImgTo3DCategory = .bathtub
    ) -> some View {
        NavigationStack {
            ImgTo3DView(initialCategory: initialCategory) {
                // 저장 직후 원래 목록으로 돌아오면 새 항목을 곧바로 선택할 수 있다.
                isPresented.wrappedValue = false
            }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(SpatiumTheme.background.ignoresSafeArea())
                .navigationTitle(initialCategory == .figure ? "소품 만들기" : "가구 만들기")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { isPresented.wrappedValue = false }
                    }
                }
        }
    }

    /// 시트 헤더. (기존의 거실/주방/침실 구역 메뉴는 목록에 아무 영향이 없는
    /// 웹 프런트 잔재라 제거 — 필터는 아래 카테고리 칩이 담당한다)
    private var zoneHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("어떤 가구를 놓을까요?")
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("\(visibleItems.count)개")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(SpatiumTheme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(SpatiumTheme.accent.opacity(0.09), in: Capsule())
                }
                Text("추가하면 캔버스로 돌아가 위치를 바로 조절할 수 있어요")
                    .font(.caption2)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer(minLength: 8)

            Button {
                catalogSearchFocused = false
                showCatalog = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.muted)
                    .frame(width: 32, height: 32)
                    .background(SpatiumTheme.warmPanel, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("가구 목록 닫기")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "전체"를 맨 앞에 둬 화면 밖으로 잘리지 않고, 필터 해제도 한 번에 되게.
                CategoryChip(title: "전체", systemImage: "square.grid.2x2", isActive: activeGroup == nil) {
                    selectGroup(nil)
                }
                CategoryChip(
                    title: "사용자 가구",
                    systemImage: "person.crop.square.filled.and.at.rectangle",
                    isActive: activeGroup == FurnitureCatalog.userFurnitureFilterID
                ) {
                    selectGroup(
                        activeGroup == FurnitureCatalog.userFurnitureFilterID
                            ? nil
                            : FurnitureCatalog.userFurnitureFilterID
                    )
                }
                ForEach(catalogGroups, id: \.self) { group in
                    CategoryChip(
                        title: group,
                        systemImage: furnitureGroupIcon(group),
                        isActive: activeGroup == group
                    ) {
                        selectGroup(activeGroup == group ? nil : group)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(SpatiumTheme.border.opacity(0.7)).frame(height: 1) }
    }

    private var catalogSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SpatiumTheme.soft)
            TextField("가구 검색하기", text: $catalogSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($catalogSearchFocused)
                .submitLabel(.done)
                .onSubmit { catalogSearchFocused = false }
            if !catalogSearch.isEmpty {
                Button {
                    catalogSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SpatiumTheme.soft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(SpatiumTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.sm).stroke(SpatiumTheme.border, lineWidth: 1))
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
    }

    /// 칩 선택: 가벼운 햅틱 + 리스트 전환 애니메이션.
    private func selectGroup(_ group: String?) {
        Haptics.selection()
        withAnimation(.easeOut(duration: 0.18)) {
            activeGroup = group
        }
    }

    private var catalogEmptyMessage: String {
        if !catalogSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "검색 결과가 없습니다"
        }
        switch activeGroup {
        case FurnitureCatalog.userFurnitureFilterID:
            return "등록된 사용자 가구가 없습니다"
        case FurnitureCatalog.otherGroup:
            return "기타 카테고리에 등록된 가구가 없습니다"
        default:
            return "조건에 맞는 가구가 없습니다"
        }
    }

    private var catalogEmptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.title2.weight(.semibold))
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 48, height: 48)
                .background(SpatiumTheme.warmPanel, in: Circle())
            Text(catalogEmptyMessage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.text)
            Text("검색어나 카테고리를 바꿔 다시 찾아보세요.")
                .font(.caption2)
                .foregroundStyle(SpatiumTheme.soft)
            Button("검색 조건 초기화") {
                Haptics.selection()
                withAnimation(.easeOut(duration: 0.18)) {
                    catalogSearch = ""
                    activeGroup = nil
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(SpatiumTheme.accent)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    /// 카탈로그 선택을 명시적인 완료 동작으로 만든다. 추가 후 시트를 닫아
    /// 사용자가 곧바로 캔버스에서 위치·회전·크기를 조절할 수 있게 한다.
    private func placeCatalogItem(_ item: FurnitureCatalogItem) {
        catalogSearchFocused = false
        Haptics.success()
        viewModel.place(catalogItem: item)
        showCatalog = false
        showPlacementNotice(for: item.name)
    }

    private func showPlacementNotice(for name: String) {
        placementNoticeTask?.cancel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            placementNotice = name
        }
        placementNoticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, placementNotice == name else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                placementNotice = nil
            }
        }
    }

    // MARK: - 3D 캔버스 + 오버레이

    private var canvas: some View {
        ZStack {
            RoomEditorSceneView(viewModel: viewModel)
                // 카탈로그에서 고른 뒤 배치 조절 카드가 나타나도 룸이 다시
                // 내려가지 않게, 사용자가 이동을 끝낼 때까지 상향 위치를 유지한다.
                .offset(y: shouldLiftRoomForFurniturePlacement ? -64 : 0)
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.86),
                    value: shouldLiftRoomForFurniturePlacement
                )

            VStack {
                HStack {
                    if viewModel.isSkyview { canvasBadge("Skyview 모드") }
                    if viewModel.isPersonView { canvasBadge("1인칭 · 드래그로 둘러보기 · 탭해서 이동") }
                    if viewModel.isMeasuring { canvasBadge("측정 모드") }
                    Spacer()
                }

                if let placementNotice {
                    FurniturePlacementNotice(name: placementNotice)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 4)
                }

                Spacer()
            }
            .padding(12)

            // 방이 비었을 때 안내 (가구가 없고, 카탈로그도 닫혀 있을 때)
            if viewModel.layout.furnitures.isEmpty && !showCatalog && !viewModel.isPersonView {
                emptyRoomHint
            }

            VStack(spacing: 10) {
                Spacer()

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                }

                if viewModel.isDecorating {
                    // 프런트와 동일하게 꾸미기 상태 배너·카탈로그·선택 도구만 캔버스 위에 띄운다.
                    decorControls
                } else {
                    // 카탈로그 시트가 열려 있을 땐 선택 카드를 숨겨 시트와 겹치지 않게 합니다.
                    if viewModel.selectedFurniture != nil && !showCatalog {
                        selectionControls
                    }

                    // 새 가구 위치를 잡는 동안에는 선택 카드만 남겨 조작 대상을 분명히 한다.
                    // 배치를 끝내면 시점/색상 도구 막대가 다시 나타난다.
                    // 카탈로그 시트가 떠 있을 땐 흰 도구 막대가 시트 모서리 밖으로
                    // 비쳐 보이므로 함께 숨긴다.
                    if !viewModel.isMovingSelectedFurniture && !showCatalog {
                        viewbar
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 가구 배치 중 SceneKit 뷰를 위로 올려도 아래에 갈색 캔버스가 드러나지 않게 한다.
        .background(SpatiumTheme.editorSceneBackground)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [SpatiumTheme.editorToolbar.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, SpatiumTheme.editorToolbar.opacity(0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 44)
            .allowsHitTesting(false)
        }
        .clipped()
    }

    private var emptyRoomHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("가구 추가를 눌러 배치해 보세요")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Button {
                viewModel.selectedItemID = nil
                viewModel.isMovingSelectedFurniture = false
                showCatalog = true
            } label: {
                Label("가구 추가", systemImage: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(SpatiumTheme.elevatedSurface, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(20)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
    }

    private func canvasBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(.black.opacity(0.5), in: Capsule())
    }

    private var viewbar: some View {
        ZStack(alignment: .bottom) {
            viewbarControls

            if let picker = activeSurfaceColorPicker {
                surfaceColorPalette(for: picker)
                    .offset(y: -66)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        // 팔레트가 떠도 bottom toolbar의 레이아웃 높이는 변하지 않는다.
        .frame(height: 58)
        .zIndex(2)
        .animation(.easeOut(duration: 0.16), value: activeSurfaceColorPicker)
    }

    private var viewbarControls: some View {
        HStack(spacing: 2) {
            viewbarButton(
                icon: "cube.transparent",
                title: "스카이뷰",
                isActive: viewModel.isSkyview,
                accessibilityLabel: "Skyview 보기"
            ) {
                viewModel.setViewMode(viewModel.isSkyview ? .threeD : .skyView)
                activeSurfaceColorPicker = nil
            }

            viewbarButton(
                icon: "figure.stand",
                title: "1인칭",
                isActive: viewModel.isPersonView,
                accessibilityLabel: "1인칭으로 방 안 둘러보기"
            ) {
                viewModel.setViewMode(viewModel.isPersonView ? .threeD : .person)
                activeSurfaceColorPicker = nil
            }

            Rectangle().fill(SpatiumTheme.subtleDivider).frame(width: 1, height: 26)

            surfaceColorButton(.wall)
            surfaceColorButton(.floor)

            if !viewModel.isPersonView {
                viewbarButton(
                    icon: "ruler",
                    title: "측정",
                    isActive: viewModel.isMeasuring,
                    accessibilityLabel: "측정 옵션 표시"
                ) {
                    viewModel.isMeasuring.toggle()
                    activeSurfaceColorPicker = nil
                }
            }

            viewbarButton(
                icon: "questionmark.circle",
                title: "도움말",
                isActive: false,
                accessibilityLabel: "뷰 사용법 안내"
            ) {
                showViewHelp = true
                activeSurfaceColorPicker = nil
            }
        }
        .padding(6)
        .background(SpatiumTheme.elevatedSurface, in: Capsule())
        .overlay(Capsule().stroke(SpatiumTheme.border.opacity(0.65), lineWidth: 1))
        .shadow(color: SpatiumTheme.shadow.opacity(0.22), radius: 14, y: 6)
    }

    /// 아이콘 + 소형 라벨이 붙은 하단 툴바 버튼. 아이콘만으로는 기능 구분이 어렵다는
    /// 피드백에 따라 모든 버튼에 이름을 붙인다.
    private func viewbarButton(
        icon: String,
        title: String,
        isActive: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? SpatiumTheme.accent : SpatiumTheme.controlIcon)
            .frame(width: 46, height: 46)
            .background(
                isActive ? SpatiumTheme.warmPanel : .clear,
                in: RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func surfaceColorButton(_ picker: SurfaceColorPicker) -> some View {
        viewbarButton(
            icon: picker.systemImage,
            title: picker == .wall ? "벽 색" : "바닥 색",
            isActive: activeSurfaceColorPicker == picker,
            accessibilityLabel: picker == .wall ? "벽 색깔 바꾸기" : "바닥 색깔 바꾸기"
        ) {
            withAnimation(.easeOut(duration: 0.16)) {
                activeSurfaceColorPicker = activeSurfaceColorPicker == picker ? nil : picker
            }
        }
    }

    private func surfaceColorPalette(for picker: SurfaceColorPicker) -> some View {
        let colors = picker == .wall ? Self.wallColors : Self.floorColors
        return HStack(spacing: 9) {
            Label(picker.title, systemImage: picker.systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(SpatiumTheme.text)

            Rectangle()
                .fill(SpatiumTheme.subtleDivider)
                .frame(width: 1, height: 22)

            ForEach(colors, id: \.self) { hex in
                Button {
                    if picker == .wall {
                        viewModel.setWallColor(hex)
                    } else {
                        viewModel.setFloorColor(hex)
                    }
                    activeSurfaceColorPicker = nil
                } label: {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(edHex: hex))
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.10), lineWidth: 1))
                        .overlay {
                            if isSelectedSurfaceColor(hex, for: picker) {
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(SpatiumTheme.accentLight, lineWidth: 2)
                                    .padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(picker.title) \(hex)")
            }
        }
        .padding(9)
        .background(SpatiumTheme.elevatedSurface, in: Capsule())
        .overlay(Capsule().stroke(SpatiumTheme.border.opacity(0.72), lineWidth: 1))
        .shadow(color: SpatiumTheme.shadow.opacity(0.24), radius: 14, y: 6)
        .fixedSize()
    }

    private func isSelectedSurfaceColor(_ hex: String, for picker: SurfaceColorPicker) -> Bool {
        switch picker {
        case .wall:
            viewModel.wallColorHex.caseInsensitiveCompare(hex) == .orderedSame
        case .floor:
            viewModel.floorColorHex?.caseInsensitiveCompare(hex) == .orderedSame
        }
    }

    // MARK: - 선택 컨트롤 (치수 / 회전 / 교체·제거)

    private var availableFurnitureAdjustments: [FurnitureAdjustment] {
        var adjustments: [FurnitureAdjustment] = []
        if !viewModel.selectedIsWallInfill {
            adjustments.append(.rotation)
        }
        if viewModel.selectedSupportsElevation && viewModel.selectedMaxElevationCm > 0 {
            adjustments.append(.elevation)
        }
        if viewModel.selectedSupportsResize {
            adjustments.append(.size)
        }
        return adjustments
    }

    private var activeFurnitureAdjustment: FurnitureAdjustment? {
        availableFurnitureAdjustments.contains(selectedFurnitureAdjustment)
            ? selectedFurnitureAdjustment
            : availableFurnitureAdjustments.first
    }

    private var selectionControls: some View {
        VStack(spacing: 6) {
            if let f = viewModel.selectedFurniture {
                // 이름 + 치수 한 줄
                HStack(spacing: 6) {
                    Text(f.furnitureName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.dimensionSummary(f))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(SpatiumTheme.soft)
                }

                if availableFurnitureAdjustments.count > 1 {
                    furnitureAdjustmentPicker
                }

                if let activeFurnitureAdjustment {
                    furnitureAdjustmentSlider(activeFurnitureAdjustment)
                }

                // 교체 / 제거 한 줄 — 벽 메우기 패널은 벽 구조라 이동/교체 없이
                // '개구부로 되돌리기'(= 패널 제거)만 허용한다.
                HStack(spacing: 8) {
                    if !viewModel.selectedIsWallInfill {
                        SelectionToolButton(
                            title: viewModel.isMovingSelectedFurniture ? "이동 중" : "이동",
                            systemImage: viewModel.isMovingSelectedFurniture ? "hand.raised.fill" : "hand.draw"
                        ) {
                            viewModel.isMovingSelectedFurniture.toggle()
                        }
                        SelectionToolButton(title: "교체", systemImage: "arrow.triangle.2.circlepath") {
                            viewModel.isMovingSelectedFurniture = false
                            showReplacePanel = true
                        }
                        // 꾸미기 책장(editable_ 모델)만: 피규어 올려놓기 모드 진입.
                        if viewModel.selectedIsDecoratable {
                            SelectionToolButton(title: "꾸미기", systemImage: "sparkles") {
                                Haptics.selection()
                                viewModel.beginDecorating()
                            }
                        }
                    }
                    SelectionToolButton(
                        title: viewModel.selectedIsWallInfill ? "개구부로 되돌리기" : "제거",
                        systemImage: "trash",
                        tint: SpatiumTheme.coral
                    ) {
                        // 문/창문은 '개구부로 남기기 / 벽으로 메우기'를 물어보고, 일반 가구는 바로 제거.
                        if viewModel.selectedIsReference {
                            showDeleteOptions = true
                        } else {
                            Haptics.impact(.rigid)
                            viewModel.deleteSelected()
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(SpatiumTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous).stroke(SpatiumTheme.border.opacity(0.65), lineWidth: 1))
        .shadow(color: SpatiumTheme.shadow.opacity(0.2), radius: 12, y: 5)
        .confirmationDialog("문/창문 제거", isPresented: $showDeleteOptions, titleVisibility: .visible) {
            Button("개구부로 남기기") {
                Haptics.impact(.rigid)
                viewModel.deleteSelected()
            }
            Button("벽으로 메우기") {
                Haptics.impact(.rigid)
                viewModel.fillOpeningWithWall()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("자리를 개구부(빈 공간)로 남길지, 벽으로 메울지 선택하세요.")
        }
    }

    private var furnitureAdjustmentPicker: some View {
        HStack(spacing: 3) {
            ForEach(availableFurnitureAdjustments) { adjustment in
                let isActive = activeFurnitureAdjustment == adjustment
                Button {
                    Haptics.selection()
                    selectedFurnitureAdjustment = adjustment
                } label: {
                    Label(adjustment.title, systemImage: adjustment.systemImage)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .foregroundStyle(isActive ? SpatiumTheme.accent : SpatiumTheme.soft)
                        .background(isActive ? SpatiumTheme.warmPanel : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(adjustment.title) 조절")
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(3)
        .background(SpatiumTheme.background.opacity(0.72), in: Capsule())
    }

    @ViewBuilder
    private func furnitureAdjustmentSlider(_ adjustment: FurnitureAdjustment) -> some View {
        switch adjustment {
        case .rotation:
            RotationSlider(
                degrees: viewModel.selectedRotationDegrees,
                onChange: { viewModel.setSelectedRotation(degrees: $0) },
                onEditingChanged: handleHistoryEditingChanged
            )
        case .elevation:
            ElevationSlider(
                cm: viewModel.selectedElevationCm,
                maxCm: viewModel.selectedMaxElevationCm,
                onChange: { viewModel.setSelectedElevation(cm: $0) },
                onEditingChanged: handleHistoryEditingChanged
            )
        case .size:
            HStack(spacing: 8) {
                Image(systemName: adjustment.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                Slider(
                    value: Binding(
                        get: { viewModel.selectedSizeCm },
                        set: { viewModel.setSelectedSize(cm: $0) }
                    ),
                    in: RoomEditorViewModel.furnitureSizeRangeCm,
                    step: 1,
                    onEditingChanged: { editing in
                        handleHistoryEditingChanged(editing)
                        if !editing {
                            // 조작이 끝나면 커진 발자국이 벽을 뚫지 않았는지 확인해 되민다.
                            viewModel.finishSelectedSizeAdjust()
                        }
                    }
                )
                .tint(SpatiumTheme.accent)
                Text("\(Int(viewModel.selectedSizeCm))cm")
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private func handleHistoryEditingChanged(_ editing: Bool) {
        if editing {
            viewModel.beginHistoryTransaction()
        } else {
            viewModel.endHistoryTransaction()
        }
    }

    private static func dimensionSummary(_ f: PlacedFurniture) -> String {
        func cm(_ value: Double?) -> String { value.map { "\(Int(($0 * 100).rounded()))" } ?? "-" }
        return "\(cm(f.width))·\(cm(f.depth))·\(cm(f.height)) cm"
    }

    // MARK: - 책장 꾸미기 패널

    /// 꾸미기 책장에는 저장 카테고리가 figure인 피규어·소품만 노출한다.
    private var figureItems: [FurnitureCatalogItem] {
        userFurnitureStore.catalogItems.filter(RoomEditorViewModel.isDecorFigure)
    }

    private var decorControls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.vertical, showsIndicators: true) {
                    decorControlsContent
                }
                .frame(maxHeight: verticalSizeClass == .compact ? 280 : 420)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("decor-controls-scroll")
            } else {
                decorControlsContent
                    // 수평 ScrollView가 남은 세로 공간을 전부 차지하지 않도록 콘텐츠 높이에 고정한다.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: viewModel.pendingFigure?.id)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: viewModel.selectedDecorID)
    }

    private var decorControlsContent: some View {
        VStack(spacing: 8) {
            decorModeBanner

            if let pending = viewModel.pendingFigure {
                decorPlacementBanner(pending)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let decoration = viewModel.selectedDecoration {
                decorSelectionControls(decoration)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            decorCatalog
        }
    }

    private var decorModeBanner: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        decorModeTitle
                        Spacer(minLength: 8)
                        decorDoneButton
                    }
                    Text("소품을 고른 뒤 3D 선반을 탭하거나 선반 선택 메뉴를 사용하세요")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            } else {
                HStack(spacing: 8) {
                    decorModeTitle
                    Text("소품을 고르고 선반을 탭하세요")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    decorDoneButton
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            SpatiumTheme.editorToolbar.opacity(0.95),
            in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decor-mode-banner")
    }

    private var decorModeTitle: some View {
        Label("책장 꾸미기", systemImage: "sparkles")
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
    }

    private var decorDoneButton: some View {
        Button("완료") {
            Haptics.selection()
            isReplacingDecor = false
            viewModel.endDecorating()
        }
        .font(.caption.weight(.black))
        .foregroundStyle(SpatiumTheme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white, in: Capsule())
        .buttonStyle(.pressable)
    }

    private func decorPlacementBanner(_ item: FurnitureCatalogItem) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Label("‘\(item.name)’ 소품을 놓을 선반을 선택하세요", systemImage: "hand.tap.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                    HStack(spacing: 10) {
                        decorShelfMenu(title: "선반 선택") { shelf in
                            viewModel.placePendingFigure(on: shelf)
                            announceSelectedDecorPosition()
                        }
                        Spacer(minLength: 8)
                        decorPlacementCancelButton
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.accent)
                    Text("‘\(item.name)’ 소품을 놓을 선반을 탭하세요")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    decorShelfMenu(title: "선반 선택") { shelf in
                        viewModel.placePendingFigure(on: shelf)
                        announceSelectedDecorPosition()
                    }
                    decorPlacementCancelButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            SpatiumTheme.warmPanel,
            in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                .stroke(SpatiumTheme.border.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: SpatiumTheme.shadow.opacity(0.15), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decor-placement-banner")
    }

    private var decorPlacementCancelButton: some View {
        Button("취소") {
            Haptics.selection()
            viewModel.pendingFigure = nil
            viewModel.statusMessage = nil
        }
        .font(.caption2.weight(.black))
        .foregroundStyle(SpatiumTheme.accent)
        .buttonStyle(.plain)
    }

    private func decorShelfMenu(
        title: String,
        onSelect: @escaping (DecorShelfLevel) -> Void
    ) -> some View {
        Menu {
            ForEach(viewModel.decorShelfLevels) { shelf in
                Button {
                    Haptics.selection()
                    onSelect(shelf)
                } label: {
                    Label(shelf.title, systemImage: "rectangle.stack")
                }
                .accessibilityIdentifier("decor-shelf-\(shelf.id)")
            }
        } label: {
            Label(title, systemImage: "rectangle.stack")
                .font(.caption2.weight(.black))
                .foregroundStyle(SpatiumTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(SpatiumTheme.elevatedSurface, in: Capsule())
                .overlay(Capsule().stroke(SpatiumTheme.accent.opacity(0.28), lineWidth: 1))
        }
        .disabled(viewModel.decorShelfLevels.isEmpty)
        .accessibilityIdentifier("decor-shelf-menu")
        .accessibilityHint("3D 화면을 직접 탭하지 않고 선반을 선택합니다")
    }

    private func decorSelectionControls(_ decoration: PlacedDecoration) -> some View {
        VStack(spacing: 7) {
            decorSelectionHeader(decoration)

            decorPositionControls

            RotationSlider(
                degrees: viewModel.selectedDecorRotationDegrees,
                onChange: { viewModel.setSelectedDecorRotation(degrees: $0) },
                onEditingChanged: handleHistoryEditingChanged
            )
            .accessibilityLabel("피규어 회전")
            .accessibilityValue("\(Int(viewModel.selectedDecorRotationDegrees))도")

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                Slider(
                    value: Binding(
                        get: { viewModel.selectedDecorSizeCm },
                        set: { viewModel.setSelectedDecorSize(cm: $0) }
                    ),
                    in: RoomEditorViewModel.figureSizeRangeCm,
                    step: 1,
                    onEditingChanged: handleHistoryEditingChanged
                )
                .tint(SpatiumTheme.accent)
                .accessibilityLabel("피규어 크기")
                .accessibilityValue("\(Int(viewModel.selectedDecorSizeCm))센티미터")
                Text("\(Int(viewModel.selectedDecorSizeCm))cm")
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(10)
        .background(SpatiumTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous).stroke(SpatiumTheme.border.opacity(0.7), lineWidth: 1))
        .shadow(color: SpatiumTheme.shadow.opacity(0.2), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decor-selection-controls")
    }

    @ViewBuilder
    private func decorSelectionHeader(_ decoration: PlacedDecoration) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 7) {
                decorSelectionDescription(decoration)
                HStack(spacing: 8) {
                    decorReplaceButton
                    decorDeleteButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                decorSelectionDescription(decoration)
                Spacer(minLength: 6)
                decorReplaceButton
                decorDeleteButton
            }
        }
    }

    private func decorSelectionDescription(_ decoration: PlacedDecoration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(decoration.name)
                .font(.caption.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
            Text(viewModel.selectedDecorAccessibilitySummary)
                .font(.caption2)
                .foregroundStyle(SpatiumTheme.soft)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("선택한 피규어 \(decoration.name)")
        .accessibilityValue(viewModel.selectedDecorAccessibilitySummary)
    }

    private var decorReplaceButton: some View {
        Button {
            Haptics.selection()
            isReplacingDecor.toggle()
            viewModel.pendingFigure = nil
        } label: {
            Label("교체", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2.weight(.black))
                .foregroundStyle(isReplacingDecor ? .white : SpatiumTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(isReplacingDecor ? SpatiumTheme.accent : SpatiumTheme.warmPanel, in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    private var decorDeleteButton: some View {
        Button {
            Haptics.impact(.rigid)
            isReplacingDecor = false
            viewModel.deleteSelectedDecor()
        } label: {
            Label("제거", systemImage: "trash")
                .font(.caption2.weight(.black))
                .foregroundStyle(SpatiumTheme.coral)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(SpatiumTheme.coral.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("소품 제거")
    }

    private var decorPositionControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("위치 조절")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(SpatiumTheme.soft)
                Spacer(minLength: 6)
                decorShelfMenu(title: "선반 이동") { shelf in
                    viewModel.moveSelectedDecor(to: shelf)
                    announceSelectedDecorPosition()
                }
            }

            LazyVGrid(columns: decorMovementColumns, spacing: 6) {
                ForEach(DecorNudgeDirection.allCases) { direction in
                    Button {
                        Haptics.selection()
                        viewModel.nudgeSelectedDecor(
                            deltaX: direction.delta.x,
                            deltaZ: direction.delta.z
                        )
                        announceSelectedDecorPosition()
                    } label: {
                        Label(direction.title, systemImage: direction.systemImage)
                            .font(.caption2.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(SpatiumTheme.accent)
                            .background(SpatiumTheme.warmPanel, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("decor-move-\(direction.rawValue)")
                    .accessibilityHint("5센티미터 이동합니다")
                }
            }
        }
        .padding(8)
        .background(SpatiumTheme.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }

    private var decorMovementColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: count)
    }

    private func announceSelectedDecorPosition() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: viewModel.selectedDecorAccessibilitySummary
        )
    }

    private var decorCatalog: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(isReplacingDecor ? "교체할 소품을 선택하세요" : "소품")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(isReplacingDecor ? SpatiumTheme.accent : SpatiumTheme.soft)
                if !isReplacingDecor, viewModel.selectedDecoration != nil {
                    Text("선택하면 새 소품을 추가해요")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SpatiumTheme.soft.opacity(0.78))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 7) {
                    ForEach(figureItems) { item in
                        decorCatalogButton(item)
                    }
                    createDecorItemButton
                }
                .padding(.horizontal, 1)
            }
            .frame(minHeight: 50)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(SpatiumTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous).stroke(SpatiumTheme.border.opacity(0.7), lineWidth: 1))
        .shadow(color: SpatiumTheme.shadow.opacity(0.2), radius: 10, y: 4)
        .accessibilityIdentifier("decor-catalog")
    }

    private func decorCatalogButton(_ item: FurnitureCatalogItem) -> some View {
        let isPending = viewModel.pendingFigure?.id == item.id
        return Button {
            Haptics.selection()
            if isReplacingDecor, viewModel.selectedDecoration != nil {
                viewModel.replaceSelectedDecor(with: item)
                isReplacingDecor = false
            } else {
                if isPending {
                    viewModel.pendingFigure = nil
                    viewModel.statusMessage = nil
                } else {
                    viewModel.prepareDecorPlacement(item)
                }
                isReplacingDecor = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isPending ? "hand.tap.fill" : "cube")
                    .font(.system(size: 10, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.caption2.weight(.black))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    Text(item.group)
                        .font(.caption2.weight(.medium))
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isPending ? .white : SpatiumTheme.text)
            .padding(.horizontal, 9)
            .frame(minHeight: 44)
            .background(isPending ? SpatiumTheme.accent : SpatiumTheme.warmPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isPending ? Color.clear : SpatiumTheme.border.opacity(0.72), lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(item.name) 소품")
        .accessibilityAddTraits(isPending ? .isSelected : [])
    }

    private var createDecorItemButton: some View {
        Button {
            Haptics.selection()
            showImgTo3DFromDecor = true
        } label: {
            Label(figureItems.isEmpty ? "소품 만들기" : "새 소품", systemImage: "plus")
                .font(.caption2.weight(.black))
                .foregroundStyle(SpatiumTheme.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(SpatiumTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(SpatiumTheme.accent.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("사진으로 새 소품을 만듭니다")
    }

    // MARK: - 하단 액션바

    /// 서버 저장이 불가능한 상태인지(오프라인 또는 게스트 로컬 프로젝트).
    private var isSaveUnavailable: Bool {
        viewModel.isOffline || viewModel.isGuestLocalProject
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if viewModel.hasUnsavedChanges,
               let failureMessage = viewModel.draftSaveState.failureMessage {
                draftSaveFailureRow(message: failureMessage)
            }

            HStack(spacing: 8) {
                footerStatus

                Spacer()
                Button {
                    viewModel.discardCurrentDraft()
                    dismiss()
                } label: {
                    Text("취소하기")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.pressable)

                Button {
                    Task { await viewModel.save() }
                } label: {
                    Group {
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("저장하기").font(.caption.weight(.black))
                        }
                    }
                    .foregroundStyle(.white.opacity(isSaveUnavailable ? 0.5 : 1))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(SpatiumTheme.accent.opacity(isSaveUnavailable ? 0.45 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(viewModel.isSaving || isSaveUnavailable)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    SpatiumTheme.editorToolbar.opacity(0.96),
                    SpatiumTheme.editorPanel
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: -5)
    }

    @ViewBuilder
    private var footerStatus: some View {
        if viewModel.hasUnsavedChanges {
            switch viewModel.draftSaveState {
            case .idle, .saving:
                Label("이 기기에 임시 저장 중...", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            case .saved:
                Label("이 기기에 임시 저장됨", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            case .failed:
                EmptyView()
            }
        } else if viewModel.isGuestLocalProject {
            // 게스트 프로젝트는 서버에 없어 업로드가 불가능하다. 기술 에러 대신 안내를 보여준다.
            Text("게스트 프로젝트 — 로그인하면 서버에 저장할 수 있어요")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        } else if viewModel.isOffline {
            // 로컬 편집 방은 서버 저장은 할 수 없지만, 편집 후에는 위의 로컬 임시 저장 상태를 보여준다.
            Text("편집 내용이 서버에 저장되지 않아요 — 이 기기에만 보관돼요")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
    }

    private func draftSaveFailureRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.coral)

            VStack(alignment: .leading, spacing: 1) {
                Text("임시 저장 실패")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button("다시 시도") {
                Haptics.selection()
                viewModel.retryDraftSave()
            }
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(SpatiumTheme.coral, in: Capsule())
            .buttonStyle(.pressable)
            .accessibilityLabel("임시 저장 다시 시도")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(SpatiumTheme.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SpatiumTheme.coral.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor-draft-save-failure")
    }
}

// MARK: - 하위 컴포넌트

private struct FurniturePlacementNotice: View {
    let name: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.sage)
            VStack(alignment: .leading, spacing: 1) {
                Text("‘\(name)’ 가구를 추가했어요")
                    .font(.caption.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Text("가구를 드래그해 원하는 위치에 놓아주세요")
                    .font(.caption2)
                    .foregroundStyle(SpatiumTheme.soft)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(SpatiumTheme.elevatedSurface, in: Capsule())
        .overlay(Capsule().stroke(SpatiumTheme.border.opacity(0.8), lineWidth: 1))
        .shadow(color: SpatiumTheme.shadow.opacity(0.2), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("furniture-placement-notice")
    }
}

private struct CategoryChip: View {
    let title: String
    var systemImage: String? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                }
                Text(title)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(isActive ? .white : SpatiumTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isActive ? SpatiumTheme.accent : SpatiumTheme.warmPanel, in: Capsule())
            .overlay(Capsule().stroke(isActive ? .clear : SpatiumTheme.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// 그룹별 대표 아이콘 — 카테고리 칩과 상품 행이 같은 아이콘 언어를 공유합니다.
private func furnitureGroupIcon(_ group: String) -> String {
    switch group {
    case "욕조": "bathtub.fill"
    case "침대": "bed.double.fill"
    case "의자": "chair.fill"
    case "식기 세척기", "세탁기·건조기": "washer.fill"
    case "벽난로": "fireplace.fill"
    case "오븐", "가스레인지": "oven.fill"
    case "냉장고": "refrigerator.fill"
    case "싱크대": "sink.fill"
    case "소파": "sofa.fill"
    case "책상": "table.furniture.fill"
    case "수납": "cabinet.fill"
    case "조명": "lamp.table.fill"
    case "문": "door.left.hand.open"
    case "창문": "window.vertical.open"
    case "계단": "stairs"
    case "TV": "tv.fill"
    case "변기": "toilet.fill"
    case "기타": "cube.fill"
    default: "square.grid.2x2"
    }
}

private struct CatalogProductRow: View {
    let item: FurnitureCatalogItem
    let action: () -> Void

    private var iconName: String { furnitureGroupIcon(item.group) }

    /// 실제 배치 크기를 미리 보여줘 배치 후 "생각보다 크다/작다"를 줄입니다.
    private var dimensionText: String {
        let w = Int((item.width * 100).rounded())
        let d = Int((item.depth * 100).rounded())
        let h = Int((item.height * 100).rounded())
        return "\(w)×\(d)×\(h)cm"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(SpatiumTheme.warmPanel)
                    .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.sm).stroke(SpatiumTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(SpatiumTheme.text)
                            .lineLimit(1)
                        if item.source == .user {
                            Text("내 가구")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(SpatiumTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(SpatiumTheme.accent.opacity(0.09), in: Capsule())
                        }
                    }
                    Text("\(item.group) · \(dimensionText)")
                        .font(.caption2)
                        .foregroundStyle(SpatiumTheme.soft)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.black))
                    Text("추가")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(SpatiumTheme.accent, in: Capsule())
            }
            .padding(12)
            .background(SpatiumTheme.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(item.name) 추가")
        .accessibilityHint("방에 가구를 추가하고 위치 조절 화면으로 돌아갑니다")
    }
}

/// -180 ~ 180 회전 슬라이더. 스톱(±180/±90/0) 근처에서 스냅됩니다.
private struct RotationSlider: View {
    let degrees: Double
    let onChange: (Double) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rotate.3d")
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
            Slider(
                value: Binding(get: { degrees }, set: { onChange($0) }),
                in: -180...180,
                step: 1,
                onEditingChanged: onEditingChanged
            )
            .tint(SpatiumTheme.accent)
            Text("\(Int(degrees))°")
                .font(.caption2.weight(.black).monospacedDigit())
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// 0 ~ 최대(천장) 높이 슬라이더. 선택한 가구를 바닥에서 수직으로 띄웁니다.
private struct ElevationSlider: View {
    let cm: Double
    let maxCm: Double
    let onChange: (Double) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.and.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
            Slider(
                value: Binding(get: { cm }, set: { onChange($0) }),
                in: 0...max(maxCm, 1),
                step: 1,
                onEditingChanged: onEditingChanged
            )
            .tint(SpatiumTheme.accent)
            Text("\(Int(cm))cm")
                .font(.caption2.weight(.black).monospacedDigit())
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

private struct SelectionToolButton: View {
    let title: String
    let systemImage: String
    var tint: Color = SpatiumTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(tint)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - 뷰 사용법 안내 시트

/// 뷰 바의 ? 버튼으로 여는 사용법 안내. 각 뷰(3D/스카이뷰/사람 뷰)의 제스처와
/// 가구 편집 방법을 설명하고, 현재 보고 있는 뷰에는 배지를 달아준다.
private struct ViewHelpSheet: View {
    let currentMode: RoomViewMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    modeCard(
                        mode: .threeD,
                        summary: "방 전체를 비스듬히 내려다보는 기본 시점이에요.",
                        rows: [
                            ("hand.draw", "한 손가락 드래그 — 방 돌려보기"),
                            ("hand.raised.fingers.spread", "두 손가락 드래그 — 화면 이동"),
                            ("arrow.up.left.and.arrow.down.right", "핀치 — 확대 / 축소")
                        ]
                    )
                    modeCard(
                        mode: .skyView,
                        summary: "천장에서 수직으로 내려다보는 도면 시점이에요.",
                        rows: [
                            ("hand.raised.fingers.spread", "두 손가락 드래그 — 화면 이동"),
                            ("arrow.up.left.and.arrow.down.right", "핀치 — 확대 / 축소"),
                            ("ruler", "측정 버튼(자)을 켜면 방 치수가 표시돼요")
                        ]
                    )
                    modeCard(
                        mode: .person,
                        summary: "방 안에 서서 눈높이로 걸어다니며 둘러보는 시점이에요.",
                        rows: [
                            ("hand.draw", "한 손가락 드래그 — 좌우 / 위아래 둘러보기"),
                            ("hand.tap", "바닥 탭 — 그 위치로 이동"),
                            ("hand.raised.fingers.spread", "두 손가락 드래그 — 보조 이동"),
                            ("figure.walk", "벽과 가구는 뚫고 지나갈 수 없어요")
                        ]
                    )
                    editCard
                }
                .padding(16)
            }
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("사용법 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func modeCard(mode: RoomViewMode, summary: String, rows: [(String, String)]) -> some View {
        card {
            HStack(spacing: 8) {
                Image(systemName: mode.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.accent)
                Text(mode.title)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                if mode == currentMode {
                    Text("현재 뷰")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SpatiumTheme.accent, in: Capsule())
                }
                Spacer()
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(SpatiumTheme.soft)
            ForEach(rows, id: \.1) { row in
                helpRow(systemImage: row.0, text: row.1)
            }
        }
    }

    private var editCard: some View {
        card {
            HStack(spacing: 8) {
                Image(systemName: "sofa")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.accent)
                Text("가구 편집 (모든 뷰 공통)")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Spacer()
            }
            helpRow(systemImage: "hand.tap", text: "가구를 탭 — 선택 / 빈 곳을 탭 — 선택 해제")
            helpRow(systemImage: "arrow.up.and.down.and.arrow.left.and.right", text: "선택 후 '이동'을 켜고 가구를 드래그 — 벽에 닿으면 딱 붙어요")
            helpRow(systemImage: "rotate.right", text: "선택하면 나오는 슬라이더로 회전")
            helpRow(systemImage: "arrow.up.and.down", text: "높이 슬라이더로 가구를 바닥에서 띄우기 (천장까지)")
            helpRow(systemImage: "arrow.triangle.2.circlepath", text: "교체 버튼으로 다른 가구로 바꾸기")
            helpRow(systemImage: "door.left.hand.open", text: "문·창문을 제거하면 개구부로 남길지 벽으로 메울지 고를 수 있어요")
        }
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(SpatiumTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }

    private func helpRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(SpatiumTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 색상 헬퍼

private extension Color {
    /// "#RRGGBB" 문자열에서 Color 생성.
    init(edHex: String) {
        var hex = edHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
