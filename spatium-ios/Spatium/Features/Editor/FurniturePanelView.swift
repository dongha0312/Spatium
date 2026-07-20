import SwiftUI

/// Furniture catalog sheet: group chips + keyword search + grid.
/// 프런트엔드 furniture_catalog.json과 맞춘 번들 카탈로그에 사용자가 만든 가구를
/// 병합해 보여준다. GLB가 저장된 항목은 modelFileName을 통해 실제 모델을 불러온다.
struct FurniturePanelView: View {
    var title: String = "가구 추가"
    var onPick: (FurnitureDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userFurnitureStore: UserFurnitureStore
    @State private var selectedGroup: String?
    @State private var keyword = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchField
                groupChips
                catalogGrid
            }
            .padding(16)
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SpatiumTheme.soft)
            TextField("가구 이름 검색", text: $keyword)
                .textInputAutocapitalization(.never)
        }
        .padding(12)
        .background(SpatiumTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(title: "전체", isSelected: selectedGroup == nil) {
                    selectedGroup = nil
                }
                CategoryChip(
                    title: "사용자 가구",
                    isSelected: selectedGroup == FurnitureCatalog.userFurnitureFilterID
                ) {
                    selectedGroup = selectedGroup == FurnitureCatalog.userFurnitureFilterID
                        ? nil
                        : FurnitureCatalog.userFurnitureFilterID
                }
                ForEach(FurnitureCatalog.editorGroups(in: userFurnitureStore.catalogItems), id: \.self) { group in
                    CategoryChip(title: group, isSelected: selectedGroup == group) {
                        selectedGroup = group
                    }
                }
            }
        }
    }

    private var catalogGrid: some View {
        ScrollView {
            if filteredItems.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.soft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(filteredItems) { item in
                        FurnitureTile(
                            name: item.name,
                            subtitle: (item.source == .user ? "내 가구 · " : "")
                                + dimensionLabel(width: item.width, depth: item.depth, height: item.height),
                            systemImage: Self.icon(forCategory: item.category)
                        ) {
                            onPick(Self.detail(from: item))
                            dismiss()
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var filteredItems: [FurnitureCatalogItem] {
        var items = userFurnitureStore.catalogItems
        if let selectedGroup {
            items = items.filter { FurnitureCatalog.matches($0, groupFilter: selectedGroup) }
        }
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.group.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var emptyMessage: String {
        switch selectedGroup {
        case FurnitureCatalog.userFurnitureFilterID:
            "등록된 사용자 가구가 없습니다"
        case FurnitureCatalog.otherGroup:
            "기타 카테고리에 등록된 가구가 없습니다"
        default:
            "조건에 맞는 가구가 없습니다"
        }
    }

    private func dimensionLabel(width: Double?, depth: Double?, height: Double?) -> String {
        guard let width, let depth, let height else { return "" }
        return String(format: "%.1f × %.1f × %.1fm", width, depth, height)
    }

    private static func icon(forCategory category: String) -> String {
        switch category {
        case "bathtub": return "bathtub"
        case "bed": return "bed.double"
        case "chair": return "chair"
        case "dishwasher", "washerDryer": return "washer"
        case "fireplace": return "fireplace"
        case "oven", "stove": return "oven"
        case "refrigerator": return "refrigerator"
        case "sink": return "sink"
        case "sofa": return "sofa"
        case "storage": return "cabinet"
        case "table": return "table.furniture"
        case "lamp": return "lamp.table"
        case "door": return "door.left.hand.closed"
        case "window": return "window.vertical.closed"
        case "stairs": return "stairs"
        case "television": return "tv"
        case "toilet": return "toilet"
        default: return "cube"
        }
    }

    /// 카탈로그 항목을 픽 콜백 타입(FurnitureDetail)으로 변환한다.
    /// 로컬 항목임을 표시하기 위해 furnitureId는 음수를 쓴다. (서버 아이템 ID와 충돌 방지)
    private static func detail(from item: FurnitureCatalogItem) -> FurnitureDetail {
        FurnitureDetail(
            furnitureId: -(abs(item.id.hashValue % 1_000_000) + 1),
            name: item.name,
            brand: item.source == .user ? "내 가구" : "기본",
            price: nil,
            width: item.width,
            depth: item.depth,
            height: item.height,
            thumbnailUrl: nil,
            modelUrl: nil,
            modelName: item.modelFileName
        )
    }
}

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? SpatiumTheme.accent : SpatiumTheme.surface)
                .foregroundStyle(isSelected ? .white : SpatiumTheme.text)
                .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.sm).stroke(SpatiumTheme.border.opacity(isSelected ? 0 : 1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FurnitureTile: View {
    let name: String
    let subtitle: String
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(height: 44)

                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(SpatiumTheme.soft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(SpatiumTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
