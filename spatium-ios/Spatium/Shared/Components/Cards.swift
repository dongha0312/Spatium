import SwiftUI

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .background(cardBackground)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border.opacity(0.85), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
            .shadow(color: SpatiumTheme.shadow.opacity(0.08), radius: 18, y: 8)
    }

    @ViewBuilder
    private var cardBackground: some View {
        SpatiumTheme.surface
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
                    .foregroundStyle(SpatiumTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(SpatiumTheme.accent.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.accent.opacity(0.16), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            }
        }
    }
}

struct EyebrowLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption2.weight(.black))
        .tracking(1)
        .textCase(.uppercase)
        .foregroundStyle(SpatiumTheme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(SpatiumTheme.accent.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.accent.opacity(0.14), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
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
