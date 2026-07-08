import SwiftUI

/// Furniture catalog sheet: group chips + keyword search + grid.
/// 서버 가구 API가 아직 없으므로, 프런트엔드 furniture_catalog.json과 1:1로 매핑된
/// 번들 카탈로그(FurnitureCatalog.items)를 데이터 소스로 사용한다. 각 항목은
/// 번들 GLB(modelFileName)를 갖고 있어 교체/추가 시 실제 3D 모델이 바뀐다.
struct FurniturePanelView: View {
    var title: String = "가구 추가"
    var onPick: (FurnitureDetail) -> Void

    @Environment(\.dismiss) private var dismiss
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
                ForEach(FurnitureCatalog.groups, id: \.self) { group in
                    CategoryChip(title: group, isSelected: selectedGroup == group) {
                        selectedGroup = group
                    }
                }
            }
        }
    }

    private var catalogGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(filteredItems) { item in
                    FurnitureTile(
                        name: item.name,
                        subtitle: dimensionLabel(width: item.width, depth: item.depth, height: item.height),
                        systemImage: Self.icon(forCategory: item.category)
                    ) {
                        onPick(Self.detail(from: item))
                        dismiss()
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var filteredItems: [FurnitureCatalogItem] {
        var items = FurnitureCatalog.items
        if let selectedGroup {
            items = items.filter { $0.group == selectedGroup }
        }
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.group.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func dimensionLabel(width: Double?, depth: Double?, height: Double?) -> String {
        guard let width, let depth, let height else { return "" }
        return String(format: "%.1f × %.1f × %.1fm", width, depth, height)
    }

    private static func icon(forCategory category: String) -> String {
        switch category {
        case "bed": return "bed.double"
        case "chair": return "chair"
        case "sofa": return "sofa"
        case "storage": return "cabinet"
        case "table": return "table.furniture"
        case "door": return "door.left.hand.closed"
        case "window": return "window.vertical.closed"
        default: return "cube"
        }
    }

    /// 카탈로그 항목을 픽 콜백 타입(FurnitureDetail)으로 변환한다.
    /// 로컬 항목임을 표시하기 위해 furnitureId는 음수를 쓴다. (서버 아이템 ID와 충돌 방지)
    private static func detail(from item: FurnitureCatalogItem) -> FurnitureDetail {
        FurnitureDetail(
            furnitureId: -(abs(item.id.hashValue % 1_000_000) + 1),
            name: item.name,
            brand: "기본",
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
