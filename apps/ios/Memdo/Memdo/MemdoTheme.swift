import SwiftUI

// Pretendard, not Work Sans -- Work Sans (still bundled, unreferenced below)
// has zero Hangul glyphs (verified against its cmap: 0 of 11,172 syllables),
// so in this Korean-first app it only ever affected the odd digit/Latin
// fragment; every actual Korean character silently fell back to the system
// font regardless of which MemdoTypography token was used. Pretendard covers
// Hangul + Latin in one face, so widening MemdoTypography's usage now
// actually changes what's on screen.
//
// Weights are separate static faces (Regular/SemiBold/Bold), not one
// variable font read at different weights -- Font.custom(name:).weight()
// against a single registered variable-font face does not reliably resolve
// to the requested weight on this SDK, so each weight needed is embedded and
// referenced by its own PostScript name instead.
enum MemdoTypography {
    private static let regular = "Pretendard-Regular"
    private static let semibold = "Pretendard-SemiBold"
    private static let bold = "Pretendard-Bold"

    static let body = Font.custom(regular, size: 17, relativeTo: .body)
    static let action = Font.custom(semibold, size: 15, relativeTo: .subheadline)
    static let caption = Font.custom(regular, size: 12, relativeTo: .caption)
    /// For a caption-sized label that needs emphasis (e.g. a category tag).
    /// `.weight(.semibold)` chained onto `.caption` doesn't reliably resolve
    /// against a custom static face -- Pretendard-SemiBold's family name
    /// ("Pretendard SemiBold") differs from Pretendard-Regular's ("Pretendard"),
    /// so weight-based face lookup within .caption's family wouldn't find it.
    static let captionEmphasis = Font.custom(semibold, size: 12, relativeTo: .caption)
    static let metric = Font.custom(semibold, size: 13, relativeTo: .footnote)
    static let editorialTitle = Font.custom(bold, size: 20, relativeTo: .title3)
    static let detailTitle = Font.custom(bold, size: 22, relativeTo: .title2)
    static let brand = Font.custom(bold, size: 22, relativeTo: .title2)
    /// Mirrors the system `.headline` text style (17pt semibold) that most
    /// shared components (MemdoSection's title, etc.) used before this --
    /// same size/weight, different typeface, so swapping it in doesn't
    /// change layout.
    static let sectionTitle = Font.custom(semibold, size: 17, relativeTo: .headline)
    /// Mirrors `.subheadline` (15pt regular) -- MemdoPage's subtitle text.
    static let subtitle = Font.custom(regular, size: 15, relativeTo: .subheadline)
    /// Mirrors `.body.weight(.semibold)` (17pt) -- the three shared
    /// MemdoPrimaryActionButtonStyle-family button labels.
    static let buttonLabel = Font.custom(semibold, size: 17, relativeTo: .body)
}

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
                ? UIColor(red: 1.00, green: 0.78, blue: 0.35, alpha: 1)    // amber (lifted for dark)
                : UIColor(red: 0.996, green: 0.725, blue: 0.149, alpha: 1) // #FEB926 amber
        }
    )
    static let brandSoft = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.28, green: 0.22, blue: 0.08, alpha: 1)   // deep amber
                : UIColor(red: 1.0, green: 0.97, blue: 0.87, alpha: 1)    // light amber cream
        }
    )
    static let onBrand = Color.black
    static let destructive = Color(uiColor: .systemRed)
    static let onDestructive = Color.white
    static let mine = ink
    static let mineSoft = Color(uiColor: .secondarySystemFill)
    static let google = secondaryInk
    static let googleSoft = Color(uiColor: .tertiarySystemFill)
    static let peach = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.00, green: 0.72, blue: 0.60, alpha: 1)
                : UIColor(red: 0.97, green: 0.52, blue: 0.38, alpha: 1)
        }
    )
    static let peachSoft = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.28, green: 0.18, blue: 0.14, alpha: 1)
                : UIColor(red: 1.00, green: 0.94, blue: 0.91, alpha: 1)
        }
    )
}

extension ScheduleColor {
    var swiftUIColor: Color {
        switch self {
        case .coral:  Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 1.00, green: 0.60, blue: 0.55, alpha: 1) : UIColor(red: 0.95, green: 0.36, blue: 0.29, alpha: 1) })
        case .amber:  Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 1.00, green: 0.82, blue: 0.45, alpha: 1) : UIColor(red: 0.95, green: 0.65, blue: 0.14, alpha: 1) })
        case .sage:   Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.62, green: 0.86, blue: 0.65, alpha: 1) : UIColor(red: 0.31, green: 0.67, blue: 0.35, alpha: 1) })
        case .sky:    Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.55, green: 0.80, blue: 1.00, alpha: 1) : UIColor(red: 0.19, green: 0.61, blue: 0.92, alpha: 1) })
        case .indigo: Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.72, green: 0.67, blue: 1.00, alpha: 1) : UIColor(red: 0.36, green: 0.30, blue: 0.72, alpha: 1) })
        case .violet: Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.90, green: 0.65, blue: 1.00, alpha: 1) : UIColor(red: 0.64, green: 0.28, blue: 0.84, alpha: 1) })
        }
    }

    var softSwiftUIColor: Color {
        switch self {
        case .coral:  Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.30, green: 0.14, blue: 0.13, alpha: 1) : UIColor(red: 1.00, green: 0.93, blue: 0.92, alpha: 1) })
        case .amber:  Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.28, green: 0.20, blue: 0.07, alpha: 1) : UIColor(red: 1.00, green: 0.97, blue: 0.88, alpha: 1) })
        case .sage:   Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.11, green: 0.23, blue: 0.13, alpha: 1) : UIColor(red: 0.91, green: 0.97, blue: 0.92, alpha: 1) })
        case .sky:    Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.10, green: 0.19, blue: 0.30, alpha: 1) : UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1) })
        case .indigo: Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.16, green: 0.14, blue: 0.30, alpha: 1) : UIColor(red: 0.93, green: 0.92, blue: 1.00, alpha: 1) })
        case .violet: Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(red: 0.22, green: 0.13, blue: 0.30, alpha: 1) : UIColor(red: 0.97, green: 0.93, blue: 1.00, alpha: 1) })
        }
    }
}

enum MemdoMetrics {
    static let pagePadding: CGFloat = 18
    static let rowInset: CGFloat = 12
    static let rowLeadingWidth: CGFloat = 44
    static let rowSpacing: CGFloat = 8
    static let rowContentLeading = rowInset + rowLeadingWidth + rowSpacing
    static let iconRadius: CGFloat = 8
    static let fieldRadius: CGFloat = 12
    static let contentRadius: CGFloat = 16
    static let groupRadius: CGFloat = 22
    static let widgetRadius: CGFloat = 28
    static let touchTarget: CGFloat = 44
    static let settingsRowHeight: CGFloat = 52
    static let sectionSpacing: CGFloat = 18
    static let sectionContentSpacing: CGFloat = 10
    static let tabBarClearance: CGFloat = 72
    static let bannerDismissDuration: Duration = .seconds(4)
}

struct MemdoPageBackground: View {
    var body: some View {
        MemdoTheme.background.ignoresSafeArea()
    }
}

extension View {
    func memdoSettingsRow() -> some View {
        frame(minHeight: MemdoMetrics.settingsRowHeight)
            .contentShape(Rectangle())
    }

    func memdoToggle() -> some View {
        tint(MemdoTheme.brand)
    }

    func memdoRowGroup() -> some View {
        overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
    }

    func memdoSystemList() -> some View {
        scrollContentBackground(.hidden)
            .background(MemdoTheme.background)
            .listSectionSpacing(.compact)
    }

    @ViewBuilder
    func memdoFloatingSurface(
        cornerRadius: CGFloat = MemdoMetrics.fieldRadius
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(MemdoTheme.controlOutline, lineWidth: 0.5)
                )
        }
    }
}
