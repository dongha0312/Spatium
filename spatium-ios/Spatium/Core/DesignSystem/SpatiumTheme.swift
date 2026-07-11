import SwiftUI
import UIKit

enum SpatiumTheme {
    static let ink = adaptive(light: "#1C120A", dark: "#5E4934")
    static let text = adaptive(light: "#1C120A", dark: "#F3EDE3")
    static let muted = adaptive(light: "#5A4536", dark: "#C9D1CB")
    static let soft = adaptive(light: "#735E4F", dark: "#93A19D")
    static let border = adaptive(light: "#DED4C7", dark: "#465456")
    static let background = adaptive(light: "#F2EEE6", dark: "#171D1E")
    static let surface = adaptive(light: "#FAF7F1", dark: "#313D3F")
    static let elevatedSurface = adaptive(light: "#FFFFFF", dark: "#3C4849")
    static let chromeSurface = adaptive(light: "#FAF7F1", dark: "#141A1B", darkAlpha: 0.82)
    static let accent = adaptive(light: "#5C3D2E", dark: "#C3A483")
    static let accentLight = adaptive(light: "#C4956A", dark: "#DCC2A2")
    static let brown = adaptive(light: "#5C3D2E", dark: "#C3A483")
    static let sage = adaptive(light: "#8C6840", dark: "#709072")
    static let sky = adaptive(light: "#7A9EC2", dark: "#87A1C1")
    static let warmPanel = adaptive(light: "#F2E8DC", dark: "#3A4644")
    static let editorPanel = adaptive(light: "#1F1C18", dark: "#161C1D")
    static let editorToolbar = adaptive(light: "#27231E", dark: "#1C2324")
    static let editorCanvas = adaptive(light: "#C4A882", dark: "#2A3436")
    static let coral = adaptive(light: "#B32E21", dark: "#FF9C8F")
    static let success = adaptive(light: "#3D7347", dark: "#8FC795")
    static let creamSurface = adaptive(light: "#FFFFFF", dark: "#F3EDE3")
    static let onCream = adaptive(light: "#5C3D2E", dark: "#6B4E33")
    static let controlIcon = adaptive(light: "#374151", dark: "#D6DDD8")
    static let subtleDivider = adaptive(light: "#E5E7EB", dark: "#3E4A4C")
    static let backgroundGradientMid = adaptive(light: "#F2E8DC", dark: "#1C2324")
    static let backgroundGradientEnd = adaptive(light: "#FAF7F1", dark: "#212A2B")
    static let shadow = adaptive(light: "#1C120A", dark: "#000000")

    private static func adaptive(light: String, dark: String, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hexString: dark).withAlphaComponent(darkAlpha)
                : UIColor(hexString: light)
        })
    }
}

enum SpatiumRadius {
    /// Small controls: icon badges, chips, inline pills.
    static let sm: CGFloat = 12
    /// Default control radius: buttons, list rows, inputs.
    static let md: CGFloat = 16
    /// Card and section container radius.
    static let lg: CGFloat = 22
}

enum SpatiumSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}
