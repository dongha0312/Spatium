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

/// 주요 작업을 설명과 함께 보여주는 카드형 CTA. 프로젝트 생성과 방 스캔처럼
/// 다음 단계가 명확한 화면에서 사용한다.
struct ActionCTAButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.black))
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white)

                Spacer(minLength: 4)

                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(.white, in: Circle())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
            .shadow(color: tint.opacity(0.22), radius: 12, y: 6)
            .opacity(isEnabled ? 1 : 0.45)
            .saturation(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.pressable)
        .contentShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .accessibilityHint(subtitle)
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
