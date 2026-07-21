import SwiftUI

/// 선택한 가구의 이동·회전·높이·크기·교체·제거 조작을 담당하는 편집 카드.
struct EditorFurnitureSelectionControlsView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject var viewModel: RoomEditorViewModel
    let onRequestReplacement: () -> Void

    @State private var showDeleteOptions = false
    @State private var selectedAdjustment: EditorFurnitureAdjustment = .rotation

    private var availableAdjustments: [EditorFurnitureAdjustment] {
        var adjustments: [EditorFurnitureAdjustment] = []
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

    private var activeAdjustment: EditorFurnitureAdjustment? {
        availableAdjustments.contains(selectedAdjustment)
            ? selectedAdjustment
            : availableAdjustments.first
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                ScrollView(.vertical, showsIndicators: true) {
                    controlsCard
                }
                .frame(maxHeight: 180)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("furniture-selection-controls-scroll")
            } else {
                controlsCard
            }
        }
        .confirmationDialog(
            "문/창문 제거",
            isPresented: $showDeleteOptions,
            titleVisibility: .visible
        ) {
            Button("개구부로 남기기", action: leaveOpening)
            Button("벽으로 메우기", action: fillOpening)
            Button("취소", role: .cancel) {}
        } message: {
            Text("자리를 개구부(빈 공간)로 남길지, 벽으로 메울지 선택하세요.")
        }
    }

    private var controlsCard: some View {
        VStack(spacing: 6) {
            if let furniture = viewModel.selectedFurniture {
                furnitureSummary(furniture)

                if availableAdjustments.count > 1 {
                    adjustmentPicker
                }

                if let activeAdjustment {
                    adjustmentSlider(activeAdjustment)
                }

                actionButtons
            }
        }
        .padding(8)
        .background(
            SpatiumTheme.elevatedSurface,
            in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                .stroke(SpatiumTheme.border.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: SpatiumTheme.shadow.opacity(0.2), radius: 12, y: 5)
        .accessibilityIdentifier("furniture-selection-controls")
    }

    private func furnitureSummary(_ furniture: PlacedFurniture) -> some View {
        HStack(spacing: 6) {
            Text(furniture.furnitureName)
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Self.dimensionSummary(furniture))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(SpatiumTheme.soft)
        }
    }

    private var adjustmentPicker: some View {
        HStack(spacing: 3) {
            ForEach(availableAdjustments) { adjustment in
                let isActive = activeAdjustment == adjustment
                Button {
                    selectAdjustment(adjustment)
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
    private func adjustmentSlider(_ adjustment: EditorFurnitureAdjustment) -> some View {
        switch adjustment {
        case .rotation:
            EditorRotationSlider(
                degrees: viewModel.selectedRotationDegrees,
                onChange: viewModel.setSelectedRotation,
                onEditingChanged: handleHistoryEditingChanged
            )
        case .elevation:
            EditorElevationSlider(
                cm: viewModel.selectedElevationCm,
                maxCm: viewModel.selectedMaxElevationCm,
                onChange: viewModel.setSelectedElevation,
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
                        set: viewModel.setSelectedSize
                    ),
                    in: RoomEditorViewModel.furnitureSizeRangeCm,
                    step: 1,
                    onEditingChanged: handleSizeEditingChanged
                )
                .tint(SpatiumTheme.accent)
                Text("\(Int(viewModel.selectedSizeCm))cm")
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if !viewModel.selectedIsWallInfill {
                EditorSelectionToolButton(
                    title: viewModel.isMovingSelectedFurniture ? "이동 중" : "이동",
                    systemImage: viewModel.isMovingSelectedFurniture ? "hand.raised.fill" : "hand.draw",
                    action: toggleMoving
                )
                EditorSelectionToolButton(
                    title: "교체",
                    systemImage: "arrow.triangle.2.circlepath",
                    action: onRequestReplacement
                )
                if viewModel.selectedIsDecoratable {
                    EditorSelectionToolButton(
                        title: "꾸미기",
                        systemImage: "sparkles",
                        action: beginDecorating
                    )
                }
            }
            EditorSelectionToolButton(
                title: viewModel.selectedIsWallInfill ? "개구부로 되돌리기" : "제거",
                systemImage: "trash",
                tint: SpatiumTheme.coral,
                action: requestDeletion
            )
        }
    }

    private func selectAdjustment(_ adjustment: EditorFurnitureAdjustment) {
        Haptics.selection()
        selectedAdjustment = adjustment
    }

    private func toggleMoving() {
        viewModel.isMovingSelectedFurniture.toggle()
    }

    private func beginDecorating() {
        Haptics.selection()
        viewModel.beginDecorating()
    }

    private func requestDeletion() {
        if viewModel.selectedIsReference {
            showDeleteOptions = true
        } else {
            Haptics.impact(.rigid)
            viewModel.deleteSelected()
        }
    }

    private func leaveOpening() {
        Haptics.impact(.rigid)
        viewModel.deleteSelected()
    }

    private func fillOpening() {
        Haptics.impact(.rigid)
        viewModel.fillOpeningWithWall()
    }

    private func handleHistoryEditingChanged(_ editing: Bool) {
        if editing {
            viewModel.beginHistoryTransaction()
        } else {
            viewModel.endHistoryTransaction()
        }
    }

    private func handleSizeEditingChanged(_ editing: Bool) {
        handleHistoryEditingChanged(editing)
        if !editing {
            viewModel.finishSelectedSizeAdjust()
        }
    }

    private static func dimensionSummary(_ furniture: PlacedFurniture) -> String {
        func centimeters(_ value: Double?) -> String {
            value.map { "\(Int(($0 * 100).rounded()))" } ?? "-"
        }
        return "\(centimeters(furniture.width))·\(centimeters(furniture.depth))·\(centimeters(furniture.height)) cm"
    }
}

private enum EditorFurnitureAdjustment: String, CaseIterable, Identifiable {
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

/// -180 ~ 180 회전 슬라이더. 스톱(±180/±90/0) 근처에서 스냅됩니다.
struct EditorRotationSlider: View {
    let degrees: Double
    let onChange: (Double) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rotate.3d")
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
            Slider(
                value: Binding(get: { degrees }, set: onChange),
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
private struct EditorElevationSlider: View {
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
                value: Binding(get: { cm }, set: onChange),
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

private struct EditorSelectionToolButton: View {
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
