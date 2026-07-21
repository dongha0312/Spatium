import ImageIO
import SwiftUI
import UIKit

enum ProfileImageDataDecoder {
    nonisolated static let maximumDisplayPixelDimension = 512

    nonisolated static func isDataURL(_ source: String?) -> Bool {
        source?.hasPrefix("data:") == true
    }

    nonisolated static func decode(_ source: String?) -> Data? {
        guard let source,
              isDataURL(source),
              let comma = source.firstIndex(of: ",") else {
            return nil
        }
        let metadata = source[..<comma]
        guard metadata.localizedCaseInsensitiveContains(";base64") else { return nil }
        let payload = String(source[source.index(after: comma)...])
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }

    /// SwiftUI body 재평가 때마다 base64 변환과 이미지 디코딩을 반복하지 않도록
    /// data URL 이미지를 메인 액터 밖에서 한 번만 다운샘플링한다.
    nonisolated static func decodeImageInBackground(_ source: String?) async -> UIImage? {
        let worker: Task<UIImage?, Never> = Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard !Task.isCancelled,
                      let data = decode(source),
                      let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
                    return nil
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumDisplayPixelDimension,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let image = CGImageSourceCreateThumbnailAtIndex(
                    imageSource,
                    0,
                    options as CFDictionary
                ) else {
                    return nil
                }
                return UIImage(cgImage: image)
            }
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

/// 백엔드의 data URL(base64)과 일반 HTTP 이미지 URL을 모두 표시합니다.
struct ProfileImageView<Placeholder: View>: View {
    let source: String?
    private let placeholder: () -> Placeholder
    @State private var decodedDataURLImage: DecodedDataURLImage?

    private struct DecodedDataURLImage {
        let source: String
        let image: UIImage
    }

    init(source: String?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.source = source
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if ProfileImageDataDecoder.isDataURL(source) {
                if let source,
                   let decodedDataURLImage,
                   decodedDataURLImage.source == source {
                    Image(uiImage: decodedDataURLImage.image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder()
                }
            } else if let source,
                      !source.isEmpty,
                      let url = URL(string: source) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder()
                    }
                }
            } else {
                placeholder()
            }
        }
        .task(id: source) {
            decodedDataURLImage = nil
            guard let source,
                  ProfileImageDataDecoder.isDataURL(source),
                  let image = await ProfileImageDataDecoder.decodeImageInBackground(source),
                  !Task.isCancelled else {
                return
            }
            decodedDataURLImage = DecodedDataURLImage(source: source, image: image)
        }
    }
}
