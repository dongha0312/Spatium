import SwiftUI

// MARK: - 3D 캔버스와 오버레이(뷰바·색상 팔레트·배치 안내)

enum SurfaceColorPicker: Equatable {
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

extension RoomEditorView {
    private static let wallColors = ["#F5F0EA", "#E8DCC8", "#C4956A", "#3A3A3A"]
    private static let floorColors = ["#D8C4A0", "#B08968", "#6B4A34", "#C9C9C9"]

    /// 카탈로그가 열려 있거나 새 가구의 위치를 잡는 동안에는 하단 UI가 룸을
    /// 가리므로, 두 단계를 하나의 배치 흐름으로 보고 같은 상향 위치를 유지한다.
    private var shouldLiftRoomForFurniturePlacement: Bool {
        showCatalog || viewModel.isMovingSelectedFurniture || viewModel.isDecorating
    }

    // MARK: - 3D 캔버스 + 오버레이

    var canvas: some View {
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
                HStack(alignment: .top) {
                    if viewModel.isSkyview { canvasBadge("Skyview 모드") }
                    if viewModel.isPersonView { canvasBadge("1인칭 · 드래그로 둘러보기 · 탭해서 이동") }
                    if viewModel.isMeasuring { canvasBadge("측정 모드") }
                    Spacer()
                    // 프런트엔드 room-area 배지 대응 — 측정 모드에서 실제 바닥 면적을 m²·평으로 표시.
                    if viewModel.isMeasuring, let area = viewModel.roomAreaSquareMeters {
                        roomAreaBadge(area)
                    }
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
                    EditorDecorControlsView(
                        viewModel: viewModel,
                        figureItems: figureItems,
                        onCreateFigure: { showImgTo3DFromDecor = true }
                    )
                } else {
                    // 카탈로그 시트가 열려 있을 땐 선택 카드를 숨겨 시트와 겹치지 않게 합니다.
                    if viewModel.selectedFurniture != nil && !showCatalog {
                        EditorFurnitureSelectionControlsView(
                            viewModel: viewModel,
                            onRequestReplacement: {
                                viewModel.isMovingSelectedFurniture = false
                                showReplacePanel = true
                            }
                        )
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

    /// 프런트엔드 `.room-scene-editor-room-area` 대응 — 흰 카드에 "면적 xx.xx m²  y.y 평".
    private func roomAreaBadge(_ area: Double) -> some View {
        Text(
            "면적 \(RoomEditorSceneView.Coordinator.formatSquareMeters(area))"
                + "  \(RoomEditorSceneView.Coordinator.formatPyung(area * 0.3025))"
        )
        .font(.caption2.weight(.bold))
        .foregroundStyle(SpatiumTheme.text)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(SpatiumTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SpatiumTheme.border.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: SpatiumTheme.shadow.opacity(0.18), radius: 10, y: 5)
        .accessibilityIdentifier("room-area-badge")
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

            // 프런트엔드 색 팝오버의 "기본 색상으로 되돌리기" 스와치 대응.
            // 선택 해제(nil)하면 스캔 원본 재질(박스 방은 기본색)로 복원된다.
            Button {
                if picker == .wall {
                    viewModel.setWallColor(nil)
                } else {
                    viewModel.setFloorColor(nil)
                }
                activeSurfaceColorPicker = nil
            } label: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SpatiumTheme.elevatedSurface)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SpatiumTheme.soft)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.10), lineWidth: 1))
                    .overlay {
                        if isDefaultSurfaceColorSelected(for: picker) {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(SpatiumTheme.accentLight, lineWidth: 2)
                                .padding(-3)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(picker.title) 기본 색상으로 되돌리기")

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
            viewModel.wallColorHex?.caseInsensitiveCompare(hex) == .orderedSame
        case .floor:
            viewModel.floorColorHex?.caseInsensitiveCompare(hex) == .orderedSame
        }
    }

    /// 색을 따로 고르지 않은 상태(nil = 원본 재질 유지)인지. 기본 스와치의 선택 표시에 쓴다.
    private func isDefaultSurfaceColorSelected(for picker: SurfaceColorPicker) -> Bool {
        switch picker {
        case .wall: viewModel.wallColorHex == nil
        case .floor: viewModel.floorColorHex == nil
        }
    }


    // MARK: - 책장 꾸미기 카탈로그

    /// 꾸미기 책장에는 저장 카테고리가 figure인 피규어·소품만 노출한다.
    private var figureItems: [FurnitureCatalogItem] {
        userFurnitureStore.catalogItems.filter(RoomEditorViewModel.isDecorFigure)
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
