import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// 업로드용 이미지 정규화. 백엔드 딥러닝 파이프라인(YOLO · GroundingDINO · SAM2)은
/// HEIC을 읽지 못하므로, PNG/JPEG가 아닌 포맷은 선택 시점에 PNG로 변환해 둔다.
enum ImgTo3DUploadImage {
    struct Normalized: Equatable {
        let data: Data
        let fileExtension: String
        /// 원본 파일이 PNG/JPEG가 아니어서(대표적으로 HEIC) PNG로 재인코딩됐는지.
        let convertedFromIncompatibleFormat: Bool
    }

    /// rawData가 있으면(사진 보관함) 포맷을 판별해 PNG/JPEG는 원본 그대로,
    /// 그 외(HEIC 등)는 PNG로 변환한다. rawData가 없으면(카메라 촬영) PNG로 인코딩한다.
    static func normalize(image: UIImage, rawData: Data?) -> Normalized? {
        if let rawData, let type = sourceType(of: rawData) {
            if type.conforms(to: .png) {
                return Normalized(data: rawData, fileExtension: "png", convertedFromIncompatibleFormat: false)
            }
            if type.conforms(to: .jpeg) {
                return Normalized(data: rawData, fileExtension: "jpg", convertedFromIncompatibleFormat: false)
            }
            guard let png = image.pngData() else { return nil }
            return Normalized(data: png, fileExtension: "png", convertedFromIncompatibleFormat: true)
        }
        guard let png = image.pngData() else { return nil }
        return Normalized(data: png, fileExtension: "png", convertedFromIncompatibleFormat: false)
    }

    private static func sourceType(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String? else { return nil }
        return UTType(identifier)
    }
}

enum ImgTo3DStep: Int, CaseIterable, Identifiable {
    case upload
    case name
    case segmentation
    case generation
    case correction
    case save

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .upload: "사진 업로드"
        case .name: "객체명 입력"
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

enum ImgTo3DCategory: String, CaseIterable, Identifiable {
    case bathtub = "욕조"
    case bed = "침대"
    case chair = "의자"
    case dishwasher = "식기 세척기"
    case fireplace = "벽난로"
    case oven = "오븐"
    case refrigerator = "냉장고"
    case sink = "싱크대"
    case sofa = "소파"
    case stairs = "계단"
    case storage = "수납"
    case stove = "가스레인지"
    case table = "책상"
    case television = "TV"
    case toilet = "변기"
    case washerDryer = "세탁기·건조기"
    case other = "기타"

    var id: String { rawValue }

    var code: String {
        switch self {
        case .bathtub: "bathtub"
        case .bed: "bed"
        case .chair: "chair"
        case .dishwasher: "dishwasher"
        case .fireplace: "fireplace"
        case .oven: "oven"
        case .refrigerator: "refrigerator"
        case .sink: "sink"
        case .sofa: "sofa"
        case .stairs: "stairs"
        case .storage: "storage"
        case .stove: "stove"
        case .table: "table"
        case .television: "television"
        case .toilet: "toilet"
        case .washerDryer: "washerDryer"
        case .other: "other"
        }
    }
}

enum ImgTo3DSegmentationProvider: String, CaseIterable, Identifiable {
    case groundedSAM2 = "grounded_sam2"
    case yolo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .groundedSAM2: "GroundingDINO + SAM2"
        case .yolo: "YOLO"
        }
    }
}

enum ImgTo3DGenerationProvider: String, CaseIterable, Identifiable {
    case localTripoSR = "local_triposr"
    case localStableFast3D = "local_stable_fast_3d"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .localTripoSR: "TripoSR"
        case .localStableFast3D: "Stable Fast 3D"
        }
    }
}

enum ImgTo3DRemesh: String, CaseIterable, Identifiable {
    case none
    case triangle
    case quad

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "없음"
        case .triangle: "Triangle"
        case .quad: "Quad"
        }
    }
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
