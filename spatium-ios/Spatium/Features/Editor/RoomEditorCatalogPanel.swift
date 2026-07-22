import SwiftUI

// MARK: - 가구 카탈로그 패널(하단 시트·검색·카테고리 칩·상품 행)

extension RoomEditorView {
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

    // MARK: - 좌측(상단) 가구 카탈로그 패널

    /// 가구 카탈로그 — 끌어올리는 하단 시트. medium 높이에선 뒤 캔버스를 그대로 조작할 수 있어
    /// 상품을 담으면 방에 바로 나타나는 걸 보면서 작업할 수 있습니다.
    var catalogSheet: some View {
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
    func imgTo3DCover(
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
    case "수납", "수납/편집 가능": "cabinet.fill"
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
