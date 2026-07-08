import SwiftUI

/// HIG "provide feedback" — 커스텀(.plain) 버튼도 눌렀을 때 즉각 반응하도록
/// 살짝 눌리고 흐려지는 공용 스타일. 탭 가능한 요소면 어디든 붙일 수 있습니다.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

struct PrimaryButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    // HIG "Buttons" — 비활성 상태는 시각적으로 구분되어야 합니다.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [SpatiumTheme.accentLight, SpatiumTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
                .saturation(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.pressable)
        .contentShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }
}

struct SecondaryButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(SpatiumTheme.warmPanel)
                .foregroundStyle(SpatiumTheme.accent)
                .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.pressable)
        .contentShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }
}
