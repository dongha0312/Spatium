import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [SpatiumTheme.accentLight, SpatiumTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Rectangle()
                .stroke(.white, lineWidth: size * 0.05)
                .frame(width: size * 0.38, height: size * 0.38)
        }
        .frame(width: size, height: size)
    }
}
