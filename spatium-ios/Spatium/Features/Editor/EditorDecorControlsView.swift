import SwiftUI
import UIKit

/// 책장 꾸미기 모드의 상태 배너, 피규어 편집 카드와 소품 카탈로그를 묶은 화면 컴포넌트.
struct EditorDecorControlsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject var viewModel: RoomEditorViewModel
    let figureItems: [FurnitureCatalogItem]
    let onCreateFigure: () -> Void

    @State private var isReplacingDecor = false

    private var usesScrollableLayout: Bool {
        dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact
    }

    private var maximumControlsHeight: CGFloat {
        verticalSizeClass == .compact ? 180 : 420
    }

    private var movementColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: count)
    }

    var body: some View {
        Group {
            if usesScrollableLayout {
                ScrollView(.vertical, showsIndicators: true) {
                    controlsContent
                }
                .frame(maxHeight: maximumControlsHeight)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("decor-controls-scroll")
            } else {
                controlsContent
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: viewModel.pendingFigure?.id)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: viewModel.selectedDecorID)
        .onChange(of: viewModel.selectedDecorID) { _, selectedDecorID in
            if selectedDecorID == nil {
                isReplacingDecor = false
            }
        }
    }

    private var controlsContent: some View {
        VStack(spacing: 8) {
            modeBanner

            if let pending = viewModel.pendingFigure {
                placementBanner(pending)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let decoration = viewModel.selectedDecoration {
                selectionControls(decoration)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            catalog
        }
    }

    private var modeBanner: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        modeTitle
                        Spacer(minLength: 8)
                        doneButton
                    }
                    Text("소품을 고른 뒤 3D 선반을 탭하거나 선반 선택 메뉴를 사용하세요")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            } else {
                HStack(spacing: 8) {
                    modeTitle
                    Text("소품을 고르고 선반을 탭하세요")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    doneButton
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

    private var modeTitle: some View {
        Label("책장 꾸미기", systemImage: "sparkles")
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
    }

    private var doneButton: some View {
        Button("완료", action: finishDecorating)
            .font(.caption.weight(.black))
            .foregroundStyle(SpatiumTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.white, in: Capsule())
            .buttonStyle(.pressable)
    }

    private func placementBanner(_ item: FurnitureCatalogItem) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Label("‘\(item.name)’ 소품을 놓을 선반을 선택하세요", systemImage: "hand.tap.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                    HStack(spacing: 10) {
                        shelfMenu(title: "선반 선택", onSelect: placePendingFigure)
                        Spacer(minLength: 8)
                        placementCancelButton
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
                    shelfMenu(title: "선반 선택", onSelect: placePendingFigure)
                    placementCancelButton
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

    private var placementCancelButton: some View {
        Button("취소", action: cancelPendingPlacement)
            .font(.caption2.weight(.black))
            .foregroundStyle(SpatiumTheme.accent)
            .buttonStyle(.plain)
    }

    private func shelfMenu(
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

    private func selectionControls(_ decoration: PlacedDecoration) -> some View {
        VStack(spacing: 7) {
            selectionHeader(decoration)
            positionControls

            EditorRotationSlider(
                degrees: viewModel.selectedDecorRotationDegrees,
                onChange: viewModel.setSelectedDecorRotation,
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
                        set: viewModel.setSelectedDecorSize
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
        .background(
            SpatiumTheme.elevatedSurface,
            in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                .stroke(SpatiumTheme.border.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: SpatiumTheme.shadow.opacity(0.2), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decor-selection-controls")
    }

    @ViewBuilder
    private func selectionHeader(_ decoration: PlacedDecoration) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 7) {
                selectionDescription(decoration)
                HStack(spacing: 8) {
                    replaceButton
                    deleteButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                selectionDescription(decoration)
                Spacer(minLength: 6)
                replaceButton
                deleteButton
            }
        }
    }

    private func selectionDescription(_ decoration: PlacedDecoration) -> some View {
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

    private var replaceButton: some View {
        Button(action: toggleReplacement) {
            Label("교체", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2.weight(.black))
                .foregroundStyle(isReplacingDecor ? .white : SpatiumTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(isReplacingDecor ? SpatiumTheme.accent : SpatiumTheme.warmPanel, in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    private var deleteButton: some View {
        Button(action: deleteSelectedDecor) {
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

    private var positionControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("위치 조절")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(SpatiumTheme.soft)
                Spacer(minLength: 6)
                shelfMenu(title: "선반 이동", onSelect: moveSelectedDecor)
            }

            LazyVGrid(columns: movementColumns, spacing: 6) {
                ForEach(EditorDecorNudgeDirection.allCases) { direction in
                    Button {
                        nudgeSelectedDecor(direction)
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

    private var catalog: some View {
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
                        catalogButton(item)
                    }
                    createItemButton
                }
                .padding(.horizontal, 1)
            }
            .frame(minHeight: 50)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            SpatiumTheme.elevatedSurface,
            in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                .stroke(SpatiumTheme.border.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: SpatiumTheme.shadow.opacity(0.2), radius: 10, y: 4)
        .accessibilityIdentifier("decor-catalog")
    }

    private func catalogButton(_ item: FurnitureCatalogItem) -> some View {
        let isPending = viewModel.pendingFigure?.id == item.id
        return Button {
            selectCatalogItem(item, isPending: isPending)
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
            .background(
                isPending ? SpatiumTheme.accent : SpatiumTheme.warmPanel,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isPending ? Color.clear : SpatiumTheme.border.opacity(0.72), lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(item.name) 소품")
        .accessibilityAddTraits(isPending ? .isSelected : [])
    }

    private var createItemButton: some View {
        Button(action: createFigure) {
            Label(figureItems.isEmpty ? "소품 만들기" : "새 소품", systemImage: "plus")
                .font(.caption2.weight(.black))
                .foregroundStyle(SpatiumTheme.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(
                    SpatiumTheme.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SpatiumTheme.accent.opacity(0.32), lineWidth: 1)
                )
        }
        .buttonStyle(.pressable)
        .accessibilityHint("사진으로 새 소품을 만듭니다")
    }

    private func finishDecorating() {
        Haptics.selection()
        isReplacingDecor = false
        viewModel.endDecorating()
    }

    private func placePendingFigure(on shelf: DecorShelfLevel) {
        viewModel.placePendingFigure(on: shelf)
        announceSelectedDecorPosition()
    }

    private func cancelPendingPlacement() {
        Haptics.selection()
        viewModel.pendingFigure = nil
        viewModel.statusMessage = nil
    }

    private func toggleReplacement() {
        Haptics.selection()
        isReplacingDecor.toggle()
        viewModel.pendingFigure = nil
    }

    private func deleteSelectedDecor() {
        Haptics.impact(.rigid)
        isReplacingDecor = false
        viewModel.deleteSelectedDecor()
    }

    private func moveSelectedDecor(to shelf: DecorShelfLevel) {
        viewModel.moveSelectedDecor(to: shelf)
        announceSelectedDecorPosition()
    }

    private func nudgeSelectedDecor(_ direction: EditorDecorNudgeDirection) {
        Haptics.selection()
        viewModel.nudgeSelectedDecor(deltaX: direction.delta.x, deltaZ: direction.delta.z)
        announceSelectedDecorPosition()
    }

    private func selectCatalogItem(_ item: FurnitureCatalogItem, isPending: Bool) {
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
    }

    private func createFigure() {
        Haptics.selection()
        onCreateFigure()
    }

    private func handleHistoryEditingChanged(_ editing: Bool) {
        if editing {
            viewModel.beginHistoryTransaction()
        } else {
            viewModel.endHistoryTransaction()
        }
    }

    private func announceSelectedDecorPosition() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: viewModel.selectedDecorAccessibilitySummary
        )
    }
}

private enum EditorDecorNudgeDirection: String, CaseIterable, Identifiable {
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
