import SwiftUI

enum MemdoTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color(uiColor: .label)
    static let secondaryInk = Color(uiColor: .secondaryLabel)
    static let outline = Color(uiColor: .separator)
    static let controlOutline = Color(uiColor: .tertiaryLabel)
    static let accent = Color(uiColor: .label)
    static let onAccent = Color(uiColor: .systemBackground)
    static let accentSoft = Color(uiColor: .tertiarySystemFill)
    static let brand = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.72, green: 0.67, blue: 1, alpha: 1)
                : UIColor(red: 0.36, green: 0.30, blue: 0.72, alpha: 1)
        }
    )
    static let brandSoft = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.20, blue: 0.31, alpha: 1)
                : UIColor(red: 0.94, green: 0.93, blue: 1, alpha: 1)
        }
    )
    static let mine = ink
    static let mineSoft = Color(uiColor: .secondarySystemFill)
    static let google = secondaryInk
    static let googleSoft = Color(uiColor: .tertiarySystemFill)
    static let peach = brand
    static let peachSoft = brandSoft
}

enum MemdoMetrics {
    static let pagePadding: CGFloat = 18
    static let cardRadius: CGFloat = 16
    static let fieldRadius: CGFloat = 12
    static let touchTarget: CGFloat = 44
    static let sectionSpacing: CGFloat = 20
    static let tabBarClearance: CGFloat = 72
}

struct MemdoPageBackground: View {
    var body: some View {
        MemdoTheme.background.ignoresSafeArea()
    }
}

extension View {
    func memdoCard(radius: CGFloat = MemdoMetrics.cardRadius) -> some View {
        background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func memdoSettingsRow() -> some View {
        frame(minHeight: 52)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    func memdoFloatingSurface(radius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .rect(cornerRadius: radius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(MemdoTheme.controlOutline)
                )
        }
    }
}
