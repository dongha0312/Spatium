import Foundation

enum ImgTo3DStep: Int, CaseIterable, Identifiable {
    case upload
    case name
    case detection
    case segmentation
    case generation
    case correction
    case save

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .upload: "사진 업로드"
        case .name: "객체명 입력"
        case .detection: "객체 선택"
        case .segmentation: "배경 제거"
        case .generation: "3D 생성"
        case .correction: "모델 보정"
        case .save: "저장"
        }
    }

    var shortTitle: String {
        switch self {
        case .upload: "사진"
        case .name: "이름"
        case .detection: "선택"
        case .segmentation: "분리"
        case .generation: "생성"
        case .correction: "보정"
        case .save: "저장"
        }
    }

    var next: ImgTo3DStep? { ImgTo3DStep(rawValue: rawValue + 1) }
    var previous: ImgTo3DStep? { ImgTo3DStep(rawValue: rawValue - 1) }
}

struct ImgTo3DNormalizedName: Equatable {
    let input: String
    let english: String
    let tags: [String]
}

struct ImgTo3DDetection: Identifiable, Equatable {
    let id: Int
    let label: String
    let score: Double
    /// 이미지 크기에 대한 0...1 정규화 좌표.
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum ImgTo3DMockPipeline {
    private struct NameEntry {
        let matches: [String]
        let english: String
        let tags: [String]
    }

    private static let names = [
        NameEntry(matches: ["협탁", "침대 옆"], english: "nightstand / bedside table", tags: ["nightstand", "bedside table", "side table"]),
        NameEntry(matches: ["의자"], english: "chair", tags: ["chair", "armchair"]),
        NameEntry(matches: ["책상"], english: "desk", tags: ["desk", "table"]),
        NameEntry(matches: ["침대"], english: "bed", tags: ["bed", "bed frame"]),
        NameEntry(matches: ["소파"], english: "sofa / couch", tags: ["sofa", "couch"]),
        NameEntry(matches: ["옷장"], english: "wardrobe", tags: ["wardrobe", "closet"]),
        NameEntry(matches: ["선반"], english: "shelf", tags: ["shelf", "bookshelf"]),
        NameEntry(matches: ["조명", "스탠드"], english: "lamp", tags: ["lamp", "floor lamp"])
    ]

    static func normalize(_ input: String) async throws -> ImgTo3DNormalizedName {
        try await Task.sleep(for: .milliseconds(900))
        try Task.checkCancellation()
        if let hit = names.first(where: { entry in
            entry.matches.contains(where: input.contains)
        }) {
            return ImgTo3DNormalizedName(input: input, english: hit.english, tags: hit.tags)
        }
        return ImgTo3DNormalizedName(input: input, english: "furniture object", tags: ["furniture", "object"])
    }

    static func detect(label: String) async throws -> [ImgTo3DDetection] {
        try await Task.sleep(for: .milliseconds(1_100))
        try Task.checkCancellation()
        return [
            .init(id: 1, label: label, score: 0.94, x: 0.12, y: 0.18, width: 0.36, height: 0.62),
            .init(id: 2, label: label, score: 0.81, x: 0.55, y: 0.30, width: 0.30, height: 0.48),
            .init(id: 3, label: label, score: 0.63, x: 0.40, y: 0.08, width: 0.22, height: 0.26)
        ]
    }
}

enum ImgTo3DCategory: String, CaseIterable, Identifiable {
    case chair = "의자"
    case table = "테이블 · 책상"
    case bed = "침대"
    case storage = "수납장"
    case light = "조명"
    case other = "기타"

    var id: String { rawValue }
}

enum ImgTo3DViewerMode: String, CaseIterable, Identifiable {
    case orbit = "보기"
    case move = "이동"
    case rotate = "회전"
    case scale = "크기"

    var id: String { rawValue }

    var hintSystemImage: String {
        switch self {
        case .orbit: "hand.draw"
        case .move: "move.3d"
        case .rotate: "rotate.3d"
        case .scale: "arrow.up.left.and.arrow.down.right"
        }
    }
}

enum ImgTo3DTransformAxis: String, CaseIterable, Identifiable {
    case free = "전체"
    case x = "X"
    case y = "Y"
    case z = "Z"

    var id: String { rawValue }
}

enum ImgTo3DCameraPreset: String, CaseIterable, Identifiable {
    case perspective = "원근"
    case front = "정면"
    case side = "측면"
    case top = "상단"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .perspective: "cube.transparent"
        case .front: "square"
        case .side: "rectangle.portrait"
        case .top: "square.grid.3x3"
        }
    }
}

struct ImgTo3DModelTransform: Equatable {
    var xDegrees: Double = 14
    var yDegrees: Double = -32
    var zDegrees: Double = 9
    var xPosition: Double = 0.35
    var yPosition: Double = 0.18
    var zPosition: Double = -0.25
    var scale: Double = 1

    static let initial = ImgTo3DModelTransform()
}

struct ImgTo3DModelSize: Equatable {
    var width: Double = 1
    var height: Double = 0.8
    var depth: Double = 0.6
}

struct ImgTo3DCorrectionSnapshot: Equatable {
    let transform: ImgTo3DModelTransform
    let floorSnap: Bool
}
