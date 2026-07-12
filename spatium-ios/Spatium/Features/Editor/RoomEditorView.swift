import SwiftUI

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

/// 3D 모델링 에디터 페이지. 프런트엔드 `3dEditor.js`의 화면 구성을 그대로 옮겼습니다.
/// 상단 내비 + 툴바, 좌측(폰=상단) 가구 카탈로그 패널, 3D 캔버스 + 하단 뷰바,
/// 하단 액션바(취소/미리보기/저장), 선택 시 치수·회전·교체·제거 컨트롤.
struct RoomEditorView: View {
    @StateObject private var viewModel: RoomEditorViewModel
    @Environment(\.dismiss) private var dismiss

    /// 같은 프로젝트의 다른 방들. 2개 이상이면 툴바의 방 이름이 드롭다운으로 바뀝니다.
    private let availableRooms: [RoomRecord]
    private let onSelectRoom: ((RoomRecord) -> Void)?

    @State private var showReplacePanel = false
    @State private var showCatalog = false
    /// 저장 안 된 변경이 있을 때 방 전환 확인용으로 보관해 두는 대상 방.
    @State private var pendingRoomSwitch: RoomRecord?
    @State private var activeGroup: String? = nil
    @State private var priceBannerVisible = true
    /// 벽/바닥 중 하나만 열리는 단일 플로팅 팔레트. 툴바 자체의 높이는 항상 고정한다.
    @State private var activeSurfaceColorPicker: SurfaceColorPicker?
    @State private var showViewHelp = false
    /// 문/창문 제거 시 '개구부로 남기기 / 벽으로 메우기' 선택 다이얼로그.
    @State private var showDeleteOptions = false

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
        guard let activeGroup else { return FurnitureCatalog.items }
        return FurnitureCatalog.items.filter { $0.group == activeGroup }
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            toolbar
            canvas
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
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-UITestCatalog") {
                showCatalog = true
            }
            if ProcessInfo.processInfo.arguments.contains("-UITestViewHelp") {
                showViewHelp = true
            }
        }
        #endif
        .sheet(isPresented: $showViewHelp) {
            ViewHelpSheet(currentMode: viewModel.viewMode)
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
                onConfirm: { onSelectRoom?(room) }
            )
        }
    }

    // MARK: - 상단 내비게이션

    private var navBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("에디터 닫기")

            Spacer()

            HStack(spacing: 7) {
                BrandMark(size: 18)
                Text("SPATIUM")
                    .font(.caption.weight(.black))
                    .tracking(4)
                    .foregroundStyle(SpatiumTheme.text)
            }

            Spacer()
            Color.clear.frame(width: 44, height: 1) // 좌우 균형용
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

    // MARK: - 툴바

    /// 서버 연결 상태 색: 온라인 초록 / 오프라인 빨강. (어두운 툴바 위에서 잘 보이는 톤)
    private var connectionColor: Color {
        viewModel.isOffline
            ? Color(red: 0.95, green: 0.42, blue: 0.36)
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

    /// 서버 연결 상태 배지 (온라인 초록 / 오프라인 빨강)
    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
            Text(viewModel.isOffline ? "오프라인" : "온라인")
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
            categoryFilters

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        CatalogProductRow(item: item) {
                            Haptics.selection()
                            viewModel.place(catalogItem: item)
                        }
                    }
                }
                .padding(14)
            }

            if priceBannerVisible {
                priceBanner
            }
        }
        .background(SpatiumTheme.surface)
        .presentationDetents([.height(360), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(360)))
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        // 시트 자체 배경(기본 회색 크롬)을 테마 서페이스로 통일해 회색이 비치지 않게.
        .presentationBackground(SpatiumTheme.surface)
    }

    /// 시트 헤더. (기존의 거실/주방/침실 구역 메뉴는 목록에 아무 영향이 없는
    /// 웹 프런트 잔재라 제거 — 필터는 아래 카테고리 칩이 담당한다)
    private var zoneHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("가구 추가")
                .font(.headline.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
            Text("탭하면 방에 바로 배치됩니다")
                .font(.caption2)
                .foregroundStyle(SpatiumTheme.soft)
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
                ForEach(FurnitureCatalog.groups, id: \.self) { group in
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

    /// 칩 선택: 가벼운 햅틱 + 리스트 전환 애니메이션.
    private func selectGroup(_ group: String?) {
        Haptics.selection()
        withAnimation(.easeOut(duration: 0.18)) {
            activeGroup = group
        }
    }

    /// 앱 웜 톤으로 통일한 안내 배너. (기존 파란색은 브랜드 팔레트 밖이라 이질감이 컸음)
    private var priceBanner: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.caption)
                .foregroundStyle(SpatiumTheme.accent)
            Text("실제 제품 가격은 판매처에 따라 다를 수 있어요.")
                .font(.caption2)
                .foregroundStyle(SpatiumTheme.muted)
            Spacer()
            Button {
                priceBannerVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SpatiumTheme.soft)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("안내 닫기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(SpatiumTheme.warmPanel)
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.sm).stroke(SpatiumTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - 3D 캔버스 + 오버레이

    private var canvas: some View {
        ZStack {
            RoomEditorSceneView(viewModel: viewModel)

            VStack {
                HStack {
                    if viewModel.isSkyview { canvasBadge("Skyview 모드") }
                    if viewModel.isPersonView { canvasBadge("사람 뷰 · 드래그로 둘러보기 · 탭해서 이동") }
                    if viewModel.isMeasuring { canvasBadge("측정 모드") }
                    Spacer()
                }
                Spacer()
            }
            .padding(12)

            // 방이 비었을 때 안내 (가구가 없고, 카탈로그도 닫혀 있을 때)
            if viewModel.layout.furnitures.isEmpty && !showCatalog {
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

                // 카탈로그 시트가 열려 있을 땐 선택 카드를 숨겨 시트와 겹치지 않게 합니다.
                if viewModel.selectedFurniture != nil && !showCatalog {
                    selectionControls
                }

                viewbar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpatiumTheme.editorCanvas)
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
                    .offset(y: -58)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        // 팔레트가 떠도 bottom toolbar의 레이아웃 높이는 변하지 않는다.
        .frame(height: 50)
        .zIndex(2)
        .animation(.easeOut(duration: 0.16), value: activeSurfaceColorPicker)
    }

    private var viewbarControls: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.setViewMode(viewModel.isSkyview ? .threeD : .skyView)
                activeSurfaceColorPicker = nil
            } label: {
                Image(systemName: "cube.transparent")
                    .font(.subheadline)
                    .foregroundStyle(viewModel.isSkyview ? SpatiumTheme.accent : SpatiumTheme.controlIcon)
                    .frame(width: 38, height: 38)
                    .background(viewModel.isSkyview ? SpatiumTheme.warmPanel : .clear, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skyview 보기")

            Button {
                viewModel.setViewMode(viewModel.isPersonView ? .threeD : .person)
                activeSurfaceColorPicker = nil
            } label: {
                Image(systemName: "figure.stand")
                    .font(.subheadline)
                    .foregroundStyle(viewModel.isPersonView ? SpatiumTheme.accent : SpatiumTheme.controlIcon)
                    .frame(width: 38, height: 38)
                    .background(viewModel.isPersonView ? SpatiumTheme.warmPanel : .clear, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("사람 뷰로 방 안 둘러보기")

            Rectangle().fill(SpatiumTheme.subtleDivider).frame(width: 1, height: 22)

            surfaceColorButton(.wall)
            surfaceColorButton(.floor)

            if !viewModel.isPersonView {
                Button {
                    viewModel.isMeasuring.toggle()
                    activeSurfaceColorPicker = nil
                } label: {
                    Image(systemName: "ruler")
                        .font(.subheadline)
                        .foregroundStyle(viewModel.isMeasuring ? SpatiumTheme.accent : SpatiumTheme.controlIcon)
                        .frame(width: 38, height: 38)
                        .background(viewModel.isMeasuring ? SpatiumTheme.warmPanel : .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("측정 옵션 표시")
            }

            Button {
                showViewHelp = true
                activeSurfaceColorPicker = nil
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(SpatiumTheme.controlIcon)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("뷰 사용법 안내")
        }
        .padding(6)
        .background(SpatiumTheme.elevatedSurface, in: Capsule())
        .overlay(Capsule().stroke(SpatiumTheme.border.opacity(0.65), lineWidth: 1))
        .shadow(color: SpatiumTheme.shadow.opacity(0.22), radius: 14, y: 6)
    }

    private func surfaceColorButton(_ picker: SurfaceColorPicker) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                activeSurfaceColorPicker = activeSurfaceColorPicker == picker ? nil : picker
            }
        } label: {
            Image(systemName: picker.systemImage)
                .font(.subheadline)
                .foregroundStyle(activeSurfaceColorPicker == picker ? SpatiumTheme.accent : SpatiumTheme.controlIcon)
                .frame(width: 38, height: 38)
                .background(activeSurfaceColorPicker == picker ? SpatiumTheme.warmPanel : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(picker == .wall ? "벽 색깔 바꾸기" : "바닥 색깔 바꾸기")
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

    private var selectionControls: some View {
        VStack(spacing: 8) {
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

                // 회전 한 줄 (아이콘 + 슬라이더 + 값) — 벽 메우기 패널은 벽이라 회전 불가.
                if !viewModel.selectedIsWallInfill {
                    RotationSlider(
                        degrees: viewModel.selectedRotationDegrees,
                        onChange: { viewModel.setSelectedRotation(degrees: $0) }
                    )
                }

                // 높이(수직) 한 줄 — 일반 가구만, 천장까지 여유가 있을 때만 표시.
                if viewModel.selectedSupportsElevation && viewModel.selectedMaxElevationCm > 0 {
                    ElevationSlider(
                        cm: viewModel.selectedElevationCm,
                        maxCm: viewModel.selectedMaxElevationCm,
                        onChange: { viewModel.setSelectedElevation(cm: $0) }
                    )
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
        .padding(10)
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

    private static func dimensionSummary(_ f: PlacedFurniture) -> String {
        func cm(_ value: Double?) -> String { value.map { "\(Int(($0 * 100).rounded()))" } ?? "-" }
        return "\(cm(f.width))·\(cm(f.depth))·\(cm(f.height)) cm"
    }

    // MARK: - 하단 액션바

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
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
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(SpatiumTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(viewModel.isSaving)
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
}

// MARK: - 하위 컴포넌트

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
    case "침대": "bed.double.fill"
    case "의자": "chair.fill"
    case "소파": "sofa.fill"
    case "책상": "table.furniture.fill"
    case "수납": "cabinet.fill"
    case "문": "door.left.hand.open"
    case "창문": "window.vertical.open"
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
                    Text(item.name)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                        .lineLimit(1)
                    Text("\(item.group) · \(dimensionText)")
                        .font(.caption2)
                        .foregroundStyle(SpatiumTheme.soft)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(SpatiumTheme.accent)
            }
            .padding(12)
            .background(SpatiumTheme.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

/// -180 ~ 180 회전 슬라이더. 스톱(±180/±90/0) 근처에서 스냅됩니다.
private struct RotationSlider: View {
    let degrees: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rotate.3d")
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
            Slider(
                value: Binding(get: { degrees }, set: { onChange($0) }),
                in: -180...180,
                step: 1
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.and.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
            Slider(
                value: Binding(get: { cm }, set: { onChange($0) }),
                in: 0...max(maxCm, 1),
                step: 1
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
