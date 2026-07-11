import SceneKit
import SwiftUI

/// 스캔 직후 방 USDZ를 실제 3D로 렌더링하고, RoomPlan이 감지한 객체(가구/문/창문)를
/// 박스 오버레이로 얹어 선택·이동·회전·이름/크기 수정·추가·삭제할 수 있는 편집기.
/// (IKEA Kreativ의 방 편집 플로우를 참고한 구성)
struct ScanEditView: View {
    @Binding var items: [EditableScanItem]
    var roomName: String
    /// 방 메시 USDZ를 지연 생성합니다. nil이면 바닥 그리드만 표시합니다.
    var usdzProvider: () throws -> URL?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItemID: UUID?
    @State private var sceneRevision = 0
    @State private var usdzURL: URL?
    @State private var isPreparingMesh = true
    @State private var showAddPanel = false
    @State private var editingItemID: UUID?
    @State private var modelPickingItemID: UUID?

    private var selectedItem: EditableScanItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            ZStack(alignment: .bottom) {
                if isPreparingMesh {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("스캔 결과를 준비하는 중...")
                            .font(.footnote)
                            .foregroundStyle(SpatiumTheme.soft)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScanEditSceneView(
                        items: $items,
                        selectedItemID: $selectedItemID,
                        sceneRevision: sceneRevision,
                        usdzURL: usdzURL
                    )
                    .ignoresSafeArea(edges: .horizontal)
                }

                bottomOverlay
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(SpatiumTheme.background.ignoresSafeArea())
        .task {
            usdzURL = try? usdzProvider()
            isPreparingMesh = false
        }
        .sheet(isPresented: $showAddPanel) {
            FurniturePanelView(title: "객체 추가") { furniture in
                addItem(from: furniture)
            }
        }
        .sheet(item: editingItemBinding) { _ in
            if let binding = bindingForItem(editingItemID) {
                ScanItemEditSheet(item: binding) {
                    sceneRevision += 1
                }
            }
        }
        .sheet(item: modelPickingBinding) { _ in
            if let binding = bindingForItem(modelPickingItemID) {
                ScanItemModelPickerSheet(item: binding) {
                    sceneRevision += 1
                }
            }
        }
    }

    private func hasSelectableModels(for item: EditableScanItem) -> Bool {
        let key = "\(item.displayName) \(item.detectedCategory) \(item.sourceType)"
        return (FurnitureCatalog.category(matching: key)?.options.count ?? 0) > 1
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Text("완료")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(SpatiumTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(roomName)
                    .font(.headline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                    .lineLimit(1)
                Text("객체 \(items.count)개")
                    .font(.caption2)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()

            Button {
                showAddPanel = true
            } label: {
                Label("객체 추가", systemImage: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(SpatiumTheme.accent.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SpatiumTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SpatiumTheme.border).frame(height: 1)
        }
    }

    // MARK: - Bottom overlay

    @ViewBuilder
    private var bottomOverlay: some View {
        if let item = selectedItem {
            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("\(item.sourceType) · \(item.measurementSummary) · 드래그로 이동")
                        .font(.caption2)
                        .foregroundStyle(SpatiumTheme.soft)
                }

                HStack(spacing: 10) {
                    ScanEditToolButton(systemImage: "pencil", title: "이름/크기") {
                        editingItemID = item.id
                    }
                    if hasSelectableModels(for: item) {
                        ScanEditToolButton(systemImage: "cube", title: "모델") {
                            modelPickingItemID = item.id
                        }
                    }
                    ScanEditToolButton(systemImage: "rotate.left", title: "좌회전") {
                        rotateSelected(byDegrees: -45)
                    }
                    ScanEditToolButton(systemImage: "rotate.right", title: "우회전") {
                        rotateSelected(byDegrees: 45)
                    }
                    ScanEditToolButton(systemImage: "trash", title: "삭제", tint: SpatiumTheme.coral) {
                        deleteSelected()
                    }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        } else if !isPreparingMesh {
            Text("객체를 탭해 선택하고, 빈 곳을 탭하면 선택이 해제됩니다")
                .font(.caption)
                .foregroundStyle(SpatiumTheme.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
        }
    }

    // MARK: - Actions

    private func addItem(from furniture: FurnitureDetail) {
        var item = EditableScanItem(
            userAddedNamed: furniture.name,
            width: furniture.width ?? 0.8,
            height: furniture.height ?? 0.8,
            depth: furniture.depth ?? 0.8
        )
        // 카탈로그에서 고른 GLB를 그대로 렌더하도록 모델 파일명을 전달한다.
        item.modelName = furniture.modelName ?? FurnitureCatalog.defaultModelName(matching: furniture.name)
        items.append(item)
        selectedItemID = item.id
        sceneRevision += 1
    }

    private func rotateSelected(byDegrees degrees: Double) {
        guard let index = items.firstIndex(where: { $0.id == selectedItemID }) else { return }
        items[index].rotationY += degrees * .pi / 180
        sceneRevision += 1
    }

    private func deleteSelected() {
        guard let selectedItemID else { return }
        items.removeAll { $0.id == selectedItemID }
        self.selectedItemID = nil
        sceneRevision += 1
    }

    private var editingItemBinding: Binding<EditableScanItem?> {
        Binding(
            get: { items.first { $0.id == editingItemID } },
            set: { if $0 == nil { editingItemID = nil } }
        )
    }

    private var modelPickingBinding: Binding<EditableScanItem?> {
        Binding(
            get: { items.first { $0.id == modelPickingItemID } },
            set: { if $0 == nil { modelPickingItemID = nil } }
        )
    }

    private func bindingForItem(_ id: UUID?) -> Binding<EditableScanItem>? {
        guard let id, let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return $items[index]
    }
}

extension EditableScanItem: Equatable {
    static func == (lhs: EditableScanItem, rhs: EditableScanItem) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ScanEditToolButton: View {
    let systemImage: String
    let title: String
    var tint: Color = SpatiumTheme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(tint)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 이름/크기 수정 시트

struct ScanItemEditSheet: View {
    @Binding var item: EditableScanItem
    var onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("이름")
                        .font(.caption.weight(.black))
                        .foregroundStyle(SpatiumTheme.soft)
                    TextField("객체 이름", text: $item.displayName)
                        .padding(12)
                        .background(SpatiumTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("크기")
                        .font(.caption.weight(.black))
                        .foregroundStyle(SpatiumTheme.soft)
                    DimensionSlider(title: "가로", value: $item.width)
                    DimensionSlider(title: "세로(깊이)", value: $item.depth)
                    DimensionSlider(title: "높이", value: $item.height)
                }

                Spacer()
            }
            .padding(20)
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("객체 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        onChanged()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 3D 모델 선택 시트

struct ScanItemModelPickerSheet: View {
    @Binding var item: EditableScanItem
    var onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var options: [FurnitureModelOption] {
        let key = "\(item.displayName) \(item.detectedCategory) \(item.sourceType)"
        return FurnitureCatalog.category(matching: key)?.options ?? []
    }

    /// 현재 적용 중인 모델(선택값이 없으면 기본 모델).
    private var currentFileName: String? {
        item.modelName ?? options.first?.fileName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if options.isEmpty {
                    Text("이 객체에 사용할 수 있는 모델이 없습니다.")
                        .font(.footnote)
                        .foregroundStyle(SpatiumTheme.soft)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                        ForEach(options) { option in
                            ModelOptionTile(
                                title: option.displayName,
                                isSelected: option.fileName == currentFileName
                            ) {
                                item.modelName = option.fileName
                                onChanged()
                                dismiss()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("모델 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ModelOptionTile: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "cube.fill")
                    .font(.title2)
                    .foregroundStyle(isSelected ? SpatiumTheme.accent : SpatiumTheme.soft)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(isSelected ? SpatiumTheme.accent.opacity(0.12) : SpatiumTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.md)
                    .stroke(isSelected ? SpatiumTheme.accent : SpatiumTheme.border, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct DimensionSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)
                Spacer()
                Text(String(format: "%.2fm", value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(SpatiumTheme.muted)
            }
            Slider(value: $value, in: 0.1...5.0, step: 0.05)
                .tint(SpatiumTheme.accent)
        }
    }
}
