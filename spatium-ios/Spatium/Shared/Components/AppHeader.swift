import SwiftUI

struct AppHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            BrandMark()

            VStack(alignment: .leading, spacing: 2) {
                Text("SPATIUM")
                    .font(.system(size: 13, weight: .black))
                    .tracking(5)
                    .foregroundStyle(SpatiumTheme.text)
                Text("Room scan workspace")
                    .font(.caption2)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()

            Text("DR")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [SpatiumTheme.accent, SpatiumTheme.brown],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .padding(5)
                .background(SpatiumTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(SpatiumTheme.border, lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(SpatiumTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SpatiumTheme.border)
                .frame(height: 1)
        }
    }
}
