import SwiftUI

struct BrandMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [SpatiumTheme.accent, SpatiumTheme.brown],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 30, height: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 12, height: 12)
            }
    }
}
