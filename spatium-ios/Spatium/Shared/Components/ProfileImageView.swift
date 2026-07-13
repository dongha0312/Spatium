import SwiftUI
import UIKit

enum ProfileImageDataDecoder {
    static func decode(_ source: String?) -> Data? {
        guard let source,
              source.hasPrefix("data:"),
              let comma = source.firstIndex(of: ",") else {
            return nil
        }
        let metadata = source[..<comma]
        guard metadata.localizedCaseInsensitiveContains(";base64") else { return nil }
        let payload = String(source[source.index(after: comma)...])
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }
}

/// 백엔드의 data URL(base64)과 일반 HTTP 이미지 URL을 모두 표시합니다.
struct ProfileImageView<Placeholder: View>: View {
    let source: String?
    private let placeholder: () -> Placeholder

    init(source: String?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.source = source
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let data = ProfileImageDataDecoder.decode(source),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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
    }
}
