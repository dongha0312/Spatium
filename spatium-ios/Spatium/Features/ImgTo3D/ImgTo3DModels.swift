import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// 업로드용 이미지 정규화. 백엔드 딥러닝 파이프라인(YOLO · GroundingDINO · SAM2)은
/// HEIC을 읽지 못하므로, PNG/JPEG가 아닌 포맷은 선택 시점에 PNG로 변환해 둔다.
/// 고해상도 원본은 ImageIO에서 바로 다운샘플링해 전체 픽셀 버퍼를 상태에 올리지 않는다.
enum ImgTo3DUploadImage {
    /// Spring `FileValidationService.AI_IMAGE_MAX_BYTES` 및 FastAPI `MAX_UPLOAD_BYTES`와 동일한 상한.
    nonisolated static let maximumUploadBytes = 10 * 1024 * 1024
    /// 객체 분리 모델 입력에는 충분한 해상도를 유지하면서 휴대폰 원본의 메모리·전송 비용을 제한한다.
    nonisolated static let maximumUploadPixelDimension = 2_048
    /// 화면에서는 최대 250pt로 표시하므로 업로드 이미지와 별도의 작은 디코딩 버퍼를 사용한다.
    nonisolated static let maximumPreviewPixelDimension = 1_024

    struct Normalized: Equatable {
        let data: Data
        let fileExtension: String
        /// 원본 파일이 PNG/JPEG가 아니어서(대표적으로 HEIC) PNG로 재인코딩됐는지.
        let convertedFromIncompatibleFormat: Bool
    }

    /// UIImage는 불변 미리보기로만 전달하고 이후 변경하지 않는다.
    struct Prepared: @unchecked Sendable {
        let previewImage: UIImage
        let upload: Normalized
    }

    /// 사진 보관함 원본의 디코딩·다운샘플링·재인코딩을 메인 액터 밖에서 수행한다.
    nonisolated static func prepareInBackground(rawData: Data) async -> Prepared? {
        let worker: Task<Prepared?, Never> = Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard !Task.isCancelled else { return nil }
                return prepare(rawData: rawData)
            }
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// 이미 서버 전송용 Data를 보관하고 있는 화면이 다시 활성화될 때, 업로드용 재인코딩 없이
    /// 화면에 필요한 작은 디코딩 버퍼만 복원한다.
    nonisolated static func previewInBackground(
        rawData: Data,
        maximumPixelDimension: Int = ImgTo3DUploadImage.maximumPreviewPixelDimension
    ) async -> UIImage? {
        let worker: Task<UIImage?, Never> = Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard !Task.isCancelled,
                      maximumPixelDimension > 0,
                      let source = CGImageSourceCreateWithData(rawData as CFData, nil),
                      let previewCGImage = downsample(
                        source: source,
                        maximumPixelDimension: maximumPixelDimension
                      ) else {
                    return nil
                }
                return decodedImage(from: previewCGImage)
            }
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// 카메라가 반환한 UIImage는 picker에서 이미 디코딩됐으므로, 읽기 전용으로 전달해
    /// 다운샘플링과 PNG 인코딩만 백그라운드에서 수행한다.
    nonisolated static func prepareInBackground(cameraImage: UIImage) async -> Prepared? {
        let immutableImage = ImmutableImage(value: cameraImage)
        let worker: Task<Prepared?, Never> = Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard !Task.isCancelled else { return nil }
                return prepare(cameraImage: immutableImage.value)
            }
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// PNG/JPEG가 이미 서버 상한과 픽셀 상한 안이면 업로드 바이트는 그대로 사용한다.
    /// 큰 원본과 HEIC 등 비호환 포맷만 방향을 보정한 축소본으로 다시 인코딩한다.
    nonisolated static func prepare(
        rawData: Data,
        maximumUploadPixelDimension: Int = ImgTo3DUploadImage.maximumUploadPixelDimension,
        maximumPreviewPixelDimension: Int = ImgTo3DUploadImage.maximumPreviewPixelDimension,
        maximumUploadBytes: Int = ImgTo3DUploadImage.maximumUploadBytes
    ) -> Prepared? {
        guard !Task.isCancelled,
              maximumUploadPixelDimension > 0,
              maximumPreviewPixelDimension > 0,
              maximumUploadBytes > 0,
              let source = CGImageSourceCreateWithData(rawData as CFData, nil),
              let sourceTypeIdentifier = CGImageSourceGetType(source) as String?,
              let sourceType = UTType(sourceTypeIdentifier),
              let sourceMaximumDimension = sourceMaximumPixelDimension(source),
              let previewCGImage = downsample(
                source: source,
                maximumPixelDimension: maximumPreviewPixelDimension
              ) else {
            return nil
        }

        let isPNG = sourceType.conforms(to: .png)
        let isJPEG = sourceType.conforms(to: .jpeg)
        let isCompatible = isPNG || isJPEG
        let needsReencoding = !isCompatible
            || sourceMaximumDimension > maximumUploadPixelDimension
            || rawData.count > maximumUploadBytes

        let uploadData: Data
        let fileExtension: String
        if needsReencoding {
            let outputType: UTType = isJPEG ? .jpeg : .png
            guard let encoded = constrainedUploadData(
                source: source,
                outputType: outputType,
                sourceMaximumPixelDimension: sourceMaximumDimension,
                maximumPixelDimension: maximumUploadPixelDimension,
                maximumBytes: maximumUploadBytes
            ) else {
                return nil
            }
            uploadData = encoded
            fileExtension = outputType.conforms(to: .jpeg) ? "jpg" : "png"
        } else {
            uploadData = rawData
            fileExtension = isJPEG ? "jpg" : "png"
        }

        guard !Task.isCancelled else { return nil }
        return Prepared(
            previewImage: decodedImage(from: previewCGImage),
            upload: Normalized(
                data: uploadData,
                fileExtension: fileExtension,
                convertedFromIncompatibleFormat: !isCompatible
            )
        )
    }

    /// 카메라 촬영 결과는 기존 계약대로 PNG로 만들되, 원본 크기의 bitmap context를
    /// 새로 만들지 않고 상한 크기의 context에 직접 그린다.
    nonisolated static func prepare(
        cameraImage: UIImage,
        maximumUploadPixelDimension: Int = ImgTo3DUploadImage.maximumUploadPixelDimension,
        maximumPreviewPixelDimension: Int = ImgTo3DUploadImage.maximumPreviewPixelDimension,
        maximumUploadBytes: Int = ImgTo3DUploadImage.maximumUploadBytes
    ) -> Prepared? {
        guard !Task.isCancelled,
              maximumUploadPixelDimension > 0,
              maximumPreviewPixelDimension > 0,
              maximumUploadBytes > 0,
              let uploadData = constrainedUploadData(
                image: cameraImage,
                outputType: .png,
                maximumPixelDimension: maximumUploadPixelDimension,
                maximumBytes: maximumUploadBytes
              ),
              let previewCGImage = downsample(
                image: cameraImage,
                maximumPixelDimension: maximumPreviewPixelDimension
              ) else {
            return nil
        }

        return Prepared(
            previewImage: decodedImage(from: previewCGImage),
            upload: Normalized(
                data: uploadData,
                fileExtension: "png",
                convertedFromIncompatibleFormat: false
            )
        )
    }

    private struct ImmutableImage: @unchecked Sendable {
        let value: UIImage
    }

    nonisolated private static func sourceMaximumPixelDimension(_ source: CGImageSource) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            return nil
        }
        return max(width, height)
    }

    nonisolated private static func downsample(
        source: CGImageSource,
        maximumPixelDimension: Int
    ) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated private static func downsample(
        image: UIImage,
        maximumPixelDimension: Int
    ) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let sourceSize = CGSize(
            width: max(1, image.size.width * image.scale),
            height: max(1, image.size.height * image.scale)
        )
        let ratio = min(1, CGFloat(maximumPixelDimension) / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(
            width: max(1, (sourceSize.width * ratio).rounded()),
            height: max(1, (sourceSize.height * ratio).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }.cgImage
    }

    nonisolated private static func constrainedUploadData(
        source: CGImageSource,
        outputType: UTType,
        sourceMaximumPixelDimension: Int,
        maximumPixelDimension: Int,
        maximumBytes: Int
    ) -> Data? {
        let initialLimit = min(sourceMaximumPixelDimension, maximumPixelDimension)
        return constrainedUploadData(
            outputType: outputType,
            initialPixelLimit: initialLimit,
            maximumBytes: maximumBytes
        ) { pixelLimit in
            downsample(source: source, maximumPixelDimension: pixelLimit)
        }
    }

    nonisolated private static func constrainedUploadData(
        image: UIImage,
        outputType: UTType,
        maximumPixelDimension: Int,
        maximumBytes: Int
    ) -> Data? {
        let sourceMaximumDimension = Int(max(
            image.size.width * image.scale,
            image.size.height * image.scale
        ).rounded(.up))
        let initialLimit = min(max(1, sourceMaximumDimension), maximumPixelDimension)
        return constrainedUploadData(
            outputType: outputType,
            initialPixelLimit: initialLimit,
            maximumBytes: maximumBytes
        ) { pixelLimit in
            downsample(image: image, maximumPixelDimension: pixelLimit)
        }
    }

    nonisolated private static func constrainedUploadData(
        outputType: UTType,
        initialPixelLimit: Int,
        maximumBytes: Int,
        makeImage: (Int) -> CGImage?
    ) -> Data? {
        var pixelLimit = max(1, initialPixelLimit)
        let minimumPixelLimit = min(
            pixelLimit,
            max(32, min(256, pixelLimit / 4))
        )

        while !Task.isCancelled {
            guard let image = makeImage(pixelLimit),
                  let data = encode(image: image, as: outputType) else {
                return nil
            }
            if data.count <= maximumBytes {
                return data
            }
            guard pixelLimit > minimumPixelLimit else { return nil }
            let nextLimit = max(minimumPixelLimit, Int(Double(pixelLimit) * 0.8))
            guard nextLimit < pixelLimit else { return nil }
            pixelLimit = nextLimit
        }
        return nil
    }

    nonisolated private static func encode(image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let properties: CFDictionary? = type.conforms(to: .jpeg)
            ? [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary
            : nil
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    nonisolated private static func decodedImage(from cgImage: CGImage) -> UIImage {
        UIImage(cgImage: cgImage, scale: 1, orientation: .up)
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
    // 3D 에디터의 "책장 꾸미기"에서 책장 위에 올려놓는 소품용 카테고리 (프런트엔드 SaveStep 대응)
    case figure = "피규어·소품"
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
        case .figure: "figure"
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

struct ImgTo3DModelTransform: Equatable, Sendable {
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
