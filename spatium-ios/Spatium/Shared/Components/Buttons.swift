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
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(SpatiumTheme.ctaFill)
                .foregroundStyle(SpatiumTheme.onCta)
                .clipShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.pressable)
        .contentShape(Capsule())
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
                    .foregroundStyle(SpatiumTheme.onCta)
                    .frame(width: 48, height: 48)
                    .background(SpatiumTheme.onCta.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.black))
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SpatiumTheme.onCta.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(SpatiumTheme.onCta)

                Spacer(minLength: 4)

                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(SpatiumTheme.ctaFill)
                    .frame(width: 34, height: 34)
                    .background(SpatiumTheme.onCta, in: Circle())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpatiumTheme.ctaFill)
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
            .shadow(color: SpatiumTheme.ctaFill.opacity(0.2), radius: 12, y: 6)
            .opacity(isEnabled ? 1 : 0.4)
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
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(SpatiumTheme.warmPanel)
                .foregroundStyle(SpatiumTheme.accent)
                .overlay(Capsule().stroke(SpatiumTheme.border, lineWidth: 1))
                .clipShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.pressable)
        .contentShape(Capsule())
    }
}
