import Foundation

/// 번들에 포함된 로컬 3D 모델(testdata) 카탈로그.
/// - `default_3d_models`의 모델을 각 카테고리의 **기본값**으로 사용하고,
/// - `3d_models/<카테고리>`의 변형(variant)들을 사용자가 고를 수 있게 노출합니다.
///
/// 번들 리소스는 폴더 구조 없이 루트로 평탄화되어 복사되므로, 조회는 파일명만으로 합니다.
nonisolated struct FurnitureModelOption: Identifiable, Hashable, Sendable {
    /// 번들 리소스 이름(확장자 제외), 예: "modern_chair".
    let fileName: String
    /// 사용자에게 보일 이름, 예: "모던 의자".
    let displayName: String

    var id: String { fileName }
}

nonisolated struct FurnitureCategoryModels: Identifiable, Sendable {
    /// 정규 카테고리 키, 예: "chair".
    let id: String
    /// 카테고리 표시 이름, 예: "의자".
    let displayName: String
    /// 매칭 키워드(영문 RoomPlan 카테고리 + 한글 이름).
    let keywords: [String]
    /// default_3d_models 기본 모델.
    let defaultOption: FurnitureModelOption
    /// 3d_models 안의 변형 모델들.
    let variantOptions: [FurnitureModelOption]

    /// 기본 모델을 맨 앞에 둔 전체 선택지.
    var options: [FurnitureModelOption] { [defaultOption] + variantOptions }
}

nonisolated enum FurnitureCatalogSource: String, Hashable, Sendable {
    case builtIn
    case user
}

/// 3D 에디터 카탈로그의 개별 상품. 프런트엔드 `furniture_catalog.json`과 동일한 구성
/// (그룹/카테고리/치수/모델 파일)을 앱 번들 GLB에 매핑합니다.
nonisolated struct FurnitureCatalogItem: Identifiable, Hashable, Sendable {
    let id: String
    /// 표시 이름, 예: "원목 침대".
    let name: String
    /// 한글 그룹 라벨(필터), 예: "침대".
    let group: String
    /// 영문 카테고리, 예: "bed".
    let category: String
    /// 미터 단위 치수(가로·높이·세로).
    let width: Double
    let height: Double
    let depth: Double
    /// 번들 GLB 파일명(확장자 제외), 예: "wooden_bed".
    let modelFileName: String
    /// 웹 에디터도 같은 GLB를 불러올 수 있는 서버/공개 경로. 번들 전용 항목은 nil이다.
    var modelPath: String? = nil
    /// 기본 제공 모델인지 사용자가 만든 모델인지 구분합니다.
    var source: FurnitureCatalogSource = .builtIn
}

nonisolated enum FurnitureCatalog {
    /// 실제 상품 그룹과 겹치지 않는 가상 필터. 사용자가 만든 모든 가구를 모아 보여줍니다.
    static let userFurnitureFilterID = "__userFurniture__"
    static let otherGroup = "기타"

    /// 프런트엔드 furniture_catalog.json과 맞춘 전체 상품 목록(22종·8그룹).
    static let items: [FurnitureCatalogItem] = [
        .init(id: "default_bed", name: "기본 침대", group: "침대", category: "bed", width: 1.2, height: 0.55, depth: 2.1, modelFileName: "bed"),
        .init(id: "wooden_bed", name: "원목 침대", group: "침대", category: "bed", width: 1.2, height: 0.55, depth: 2.1, modelFileName: "wooden_bed"),
        .init(id: "simple_bed", name: "심플 침대", group: "침대", category: "bed", width: 1.2, height: 0.55, depth: 2.1, modelFileName: "simple_bed"),
        .init(id: "default_chair", name: "기본 의자", group: "의자", category: "chair", width: 0.55, height: 0.85, depth: 0.55, modelFileName: "chair"),
        .init(id: "modern_chair", name: "모던 의자", group: "의자", category: "chair", width: 0.55, height: 0.85, depth: 0.55, modelFileName: "modern_chair"),
        .init(id: "wooden_chair", name: "원목 의자", group: "의자", category: "chair", width: 0.55, height: 0.85, depth: 0.55, modelFileName: "wooden_chair"),
        .init(id: "default_storage", name: "기본 수납", group: "수납", category: "storage", width: 1.0, height: 1.2, depth: 0.45, modelFileName: "storage"),
        // 꾸미기(피규어 올려놓기) 전용 모델 — 선반 안쪽 표면이 뚫려 있어 위에 소품을 올릴 수 있다.
        // 프런트엔드의 editable_furniture 폴더 규칙 대응: modelFileName의 "editable_" 접두사로 판정한다.
        .init(id: "def_editable_bookcase", name: "꾸미기 책장", group: "수납", category: "storage", width: 0.8, height: 1.8, depth: 0.3, modelFileName: "editable_bookcase"),
        .init(id: "closet", name: "옷장", group: "수납", category: "storage", width: 1.2, height: 2.0, depth: 0.55, modelFileName: "closet"),
        .init(id: "bedside_drawer", name: "협탁 서랍", group: "수납", category: "storage", width: 0.5, height: 0.6, depth: 0.45, modelFileName: "bedside_drawer"),
        .init(id: "makeup_table", name: "화장대", group: "수납", category: "storage", width: 1.0, height: 0.8, depth: 0.45, modelFileName: "makeup_table"),
        .init(id: "default_table", name: "기본 책상", group: "책상", category: "table", width: 1.2, height: 0.75, depth: 0.65, modelFileName: "table"),
        .init(id: "wooden_desk", name: "원목 책상", group: "책상", category: "table", width: 1.2, height: 0.75, depth: 0.65, modelFileName: "wooden_desk"),
        .init(id: "ikea_desk", name: "이케아 책상", group: "책상", category: "table", width: 1.2, height: 0.75, depth: 0.65, modelFileName: "ikea_desk"),
        .init(id: "computer_desk", name: "컴퓨터 책상", group: "책상", category: "table", width: 1.25, height: 0.75, depth: 0.7, modelFileName: "computer_desk"),
        .init(id: "default_door", name: "기본 문", group: "문", category: "door", width: 0.9, height: 2.1, depth: 0.12, modelFileName: "door"),
        .init(id: "white_door", name: "화이트 도어", group: "문", category: "door", width: 0.9, height: 2.1, depth: 0.12, modelFileName: "white_door"),
        .init(id: "wooden_door", name: "우드 도어", group: "문", category: "door", width: 0.9, height: 2.1, depth: 0.12, modelFileName: "wooden_door"),
        .init(id: "default_window", name: "기본 창문", group: "창문", category: "window", width: 0.9, height: 1.0, depth: 0.1, modelFileName: "window"),
        .init(id: "tong_glass", name: "통유리", group: "창문", category: "window", width: 0.9, height: 1.0, depth: 0.1, modelFileName: "window"),
        .init(id: "single_window", name: "싱글 창문", group: "창문", category: "window", width: 0.75, height: 1.0, depth: 0.1, modelFileName: "single_window"),
        .init(id: "double_window", name: "더블 창문", group: "창문", category: "window", width: 1.2, height: 1.0, depth: 0.1, modelFileName: "double_window"),
        .init(id: "default_stairs", name: "계단", group: "계단", category: "stairs", width: 1.2, height: 2.8, depth: 4.59, modelFileName: "stairs")
    ]

    /// 상품 등장 순서를 보존한 고유 그룹 목록(필터 칩용).
    static let groups: [String] = {
        groups(in: items)
    }()

    static func groups(in items: [FurnitureCatalogItem]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }

    /// 룸 에디터의 카테고리 순서. `기타`는 항목이 없어도 항상 마지막에 노출합니다.
    static func editorGroups(in items: [FurnitureCatalogItem]) -> [String] {
        groups(in: items).filter { $0 != otherGroup } + [otherGroup]
    }

    /// 추가/교체 화면이 공유하는 카테고리 필터 규칙입니다.
    static func matches(_ item: FurnitureCatalogItem, groupFilter: String?) -> Bool {
        guard let groupFilter else { return true }
        if groupFilter == userFurnitureFilterID {
            return item.source == .user
        }
        return item.group == groupFilter
    }

    static let categories: [FurnitureCategoryModels] = [
        .init(
            id: "chair", displayName: "의자", keywords: ["chair", "의자"],
            defaultOption: .init(fileName: "chair", displayName: "기본 의자"),
            variantOptions: [
                .init(fileName: "modern_chair", displayName: "모던 의자"),
                .init(fileName: "wooden_chair", displayName: "원목 의자")
            ]
        ),
        .init(
            id: "table", displayName: "테이블/책상", keywords: ["table", "desk", "테이블", "책상"],
            defaultOption: .init(fileName: "table", displayName: "기본 테이블"),
            variantOptions: [
                .init(fileName: "wooden_desk", displayName: "원목 책상"),
                .init(fileName: "computer_desk", displayName: "컴퓨터 책상"),
                .init(fileName: "ikea_desk", displayName: "이케아 책상")
            ]
        ),
        .init(
            id: "bed", displayName: "침대", keywords: ["bed", "침대"],
            defaultOption: .init(fileName: "bed", displayName: "기본 침대"),
            variantOptions: [
                .init(fileName: "simple_bed", displayName: "심플 침대"),
                .init(fileName: "wooden_bed", displayName: "원목 침대")
            ]
        ),
        .init(
            id: "storage", displayName: "수납장",
            keywords: ["storage", "closet", "cabinet", "drawer", "옷장", "수납", "서랍", "화장대"],
            defaultOption: .init(fileName: "storage", displayName: "기본 수납장"),
            variantOptions: [
                .init(fileName: "closet", displayName: "옷장"),
                .init(fileName: "bedside_drawer", displayName: "협탁 서랍"),
                .init(fileName: "makeup_table", displayName: "화장대")
            ]
        ),
        .init(
            id: "sofa", displayName: "소파", keywords: ["sofa", "couch", "소파"],
            defaultOption: .init(fileName: "sofa", displayName: "소파"), variantOptions: []
        ),
        .init(
            id: "refrigerator", displayName: "냉장고", keywords: ["refrigerator", "fridge", "냉장"],
            defaultOption: .init(fileName: "refrigerator", displayName: "냉장고"), variantOptions: []
        ),
        .init(
            id: "stove", displayName: "레인지", keywords: ["stove", "레인지", "가스"],
            defaultOption: .init(fileName: "stove", displayName: "가스레인지"), variantOptions: []
        ),
        .init(
            id: "oven", displayName: "오븐", keywords: ["oven", "오븐"],
            defaultOption: .init(fileName: "oven", displayName: "오븐"), variantOptions: []
        ),
        .init(
            id: "dishwasher", displayName: "식기세척기", keywords: ["dishwasher", "식기"],
            defaultOption: .init(fileName: "dishwasher", displayName: "식기세척기"), variantOptions: []
        ),
        .init(
            id: "sink", displayName: "싱크대", keywords: ["sink", "싱크"],
            defaultOption: .init(fileName: "sink", displayName: "싱크대"), variantOptions: []
        ),
        .init(
            id: "washerDryer", displayName: "세탁기", keywords: ["washer", "dryer", "세탁", "건조"],
            defaultOption: .init(fileName: "washerDryer", displayName: "세탁/건조기"), variantOptions: []
        ),
        .init(
            id: "toilet", displayName: "변기", keywords: ["toilet", "변기"],
            defaultOption: .init(fileName: "toilet", displayName: "변기"), variantOptions: []
        ),
        .init(
            id: "bathtub", displayName: "욕조", keywords: ["bathtub", "욕조"],
            defaultOption: .init(fileName: "bathtub", displayName: "욕조"), variantOptions: []
        ),
        .init(
            id: "television", displayName: "TV", keywords: ["television", "tv", "티비", "텔레비전"],
            defaultOption: .init(fileName: "television", displayName: "TV"), variantOptions: []
        ),
        .init(
            id: "door", displayName: "문", keywords: ["door", "문"],
            defaultOption: .init(fileName: "door", displayName: "기본 문"),
            variantOptions: [
                .init(fileName: "white_door", displayName: "화이트 도어"),
                .init(fileName: "wooden_door", displayName: "원목 문")
            ]
        ),
        .init(
            id: "window", displayName: "창문", keywords: ["window", "창문"],
            defaultOption: .init(fileName: "window", displayName: "기본 창문"),
            variantOptions: [
                .init(fileName: "double_window", displayName: "이중창"),
                .init(fileName: "single_window", displayName: "단창")
            ]
        )
    ]

    /// 임의의 카테고리/이름 문자열에 가장 잘 맞는 카테고리를 찾습니다.
    /// 가장 긴(구체적인) 키워드 매칭이 이깁니다 — "창문"이 door의 키워드 "문"에 먼저 걸리는 것 방지.
    static func category(matching raw: String) -> FurnitureCategoryModels? {
        let haystack = raw.lowercased()
        var best: (category: FurnitureCategoryModels, keywordLength: Int)?
        for category in categories {
            for keyword in category.keywords {
                let lowered = keyword.lowercased()
                guard haystack.contains(lowered) else { continue }
                if best == nil || lowered.count > best!.keywordLength {
                    best = (category, lowered.count)
                }
            }
        }
        return best?.category
    }

    /// 카테고리 문자열에 대한 기본 모델 파일명.
    static func defaultModelName(matching raw: String) -> String? {
        category(matching: raw)?.defaultOption.fileName
    }

    /// 파일명으로 옵션(표시 이름 포함)을 되찾습니다.
    static func option(named fileName: String) -> FurnitureModelOption? {
        for category in categories {
            if let match = category.options.first(where: { $0.fileName == fileName }) {
                return match
            }
        }
        return nil
    }
}
