import SwiftUI

private let imgTo3DModelModeTransition = Animation.spring(response: 0.3, dampingFraction: 0.82)

struct ImgTo3DModelModeButton: View {
    let mode: ImgTo3DViewerMode
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch mode {
        case .orbit: "rotate.3d"
        case .move: "move.3d"
        case .rotate: "arrow.trianglehead.2.clockwise.rotate.90"
        case .scale: "arrow.up.left.and.arrow.down.right"
        }
    }

    var body: some View {
        Button(action: action) {
            Label(mode.rawValue, systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(isSelected ? SpatiumTheme.onCta : SpatiumTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isSelected ? SpatiumTheme.ctaFill : SpatiumTheme.warmPanel)
                .overlay(Capsule().stroke(isSelected ? .clear : SpatiumTheme.border, lineWidth: 1))
                .clipShape(Capsule())
                .scaleEffect(isSelected ? 1 : 0.98)
                .animation(imgTo3DModelModeTransition, value: isSelected)
        }
        .buttonStyle(.pressable)
        .contentShape(Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ImgTo3DCorrectionIconButton: View {
    let systemImage: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.black))
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 34, height: 34)
                .background(SpatiumTheme.elevatedSurface, in: Circle())
                .overlay(Circle().stroke(SpatiumTheme.border, lineWidth: 1))
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

struct ImgTo3DCorrectionContextBar<Actions: View>: View {
    let icon: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 30, height: 30)
                .background(SpatiumTheme.elevatedSurface, in: Circle())
            Text(message)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SpatiumTheme.soft)
                .lineLimit(2)
            Spacer(minLength: 2)
            actions
        }
        .padding(8)
        .background(SpatiumTheme.warmPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
    }
}

struct ImgTo3DCorrectionQuickButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.black))
                Text(title)
                    .font(.system(size: 8, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(SpatiumTheme.accent)
            .frame(minWidth: 43, minHeight: 34)
            .padding(.horizontal, 3)
            .background(SpatiumTheme.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(SpatiumTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(title)
    }
}

struct ImgTo3DAxisButton: View {
    let axis: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(axis)
                .font(.caption2.monospaced().weight(.black))
                .foregroundStyle(isSelected ? SpatiumTheme.onCta : SpatiumTheme.accent)
                .frame(width: 27, height: 27)
                .background(isSelected ? SpatiumTheme.ctaFill : SpatiumTheme.elevatedSurface, in: Circle())
                .overlay(Circle().stroke(isSelected ? .clear : SpatiumTheme.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(axis)축")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ImgTo3DTransformValuesRow: View {
    let values: [(axis: String, value: Double, unit: String)]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    Text(item.axis)
                        .foregroundStyle(axisColor(item.axis))
                    Text(item.value, format: .number.precision(.fractionLength(2)))
                        .foregroundStyle(SpatiumTheme.text)
                    Text(item.unit)
                        .foregroundStyle(SpatiumTheme.soft)
                }
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(SpatiumTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func axisColor(_ axis: String) -> Color {
        switch axis {
        case "X": .red
        case "Y": .green
        default: .blue
        }
    }
}
