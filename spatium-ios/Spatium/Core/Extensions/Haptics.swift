import UIKit

/// HIG "Playing haptics" — 핵심 순간에 촉각 피드백을 주는 얇은 래퍼.
/// 모든 호출은 메인 스레드(UI 액션)에서 이뤄진다고 가정합니다.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
