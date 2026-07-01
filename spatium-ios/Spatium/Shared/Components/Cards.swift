import SwiftUI

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(SpatiumTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SpatiumTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.025), radius: 6, y: 2)
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.brown)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(SpatiumTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SpatiumTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String

    static let gridColumns = [
        GridItem(.adaptive(minimum: 96), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(SpatiumTheme.soft)
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SpatiumTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SpatiumTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        Card {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(SpatiumTheme.soft)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(SpatiumTheme.text)
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .foregroundStyle(SpatiumTheme.soft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }
}
