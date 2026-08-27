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
// Full scale, one token per (Apple text style x weight) combination actually
// used anywhere in the app -- see docs/28-design-system-density-and-agent-ui.md
// for the table of which token to reach for and why. Each token's doc comment
// names the system style it replaces 1:1 (same size/relativeTo, so swapping
// it into an existing call site never changes layout, only typeface) so a
// grep for ".title3" or ".footnote.weight(.semibold)" etc. finds its
// replacement without guessing.
//
// Two approximations, both intentional:
// - .weight(.medium) and .weight(.bold) call sites map onto the nearest
//   *emphasis* token (semibold) rather than getting their own Medium/Black
//   faces -- three weights (Regular/SemiBold/Bold) covers the app's actual
//   visual hierarchy; a fourth+fifth face is bundle size for a distinction
//   nobody was relying on.
// - True one-off `.system(size: N, ...)` calls (large decorative numerals,
//   icon-adjacent badges at a bespoke pixel size) are NOT in this scale and
//   were left alone -- those are deliberate custom moments, not gaps.
enum MemdoTypography {
    private static let regular = "Pretendard-Regular"
    private static let semibold = "Pretendard-SemiBold"
    private static let bold = "Pretendard-Bold"

    // MARK: Body copy

    /// Mirrors `.body` (17pt regular).
    static let body = Font.custom(regular, size: 17, relativeTo: .body)
    /// Mirrors `.body.weight(.semibold)` (17pt) -- the three shared
    /// MemdoPrimaryActionButtonStyle-family button labels.
    static let buttonLabel = Font.custom(semibold, size: 17, relativeTo: .body)

    // MARK: Headline / section title

    /// Mirrors `.headline` (17pt semibold) -- MemdoSection's title and
    /// most other section/row headers.
    static let sectionTitle = Font.custom(semibold, size: 17, relativeTo: .headline)

    // MARK: Subheadline

    /// Mirrors `.subheadline` (15pt regular) -- MemdoPage's subtitle text.
    static let subtitle = Font.custom(regular, size: 15, relativeTo: .subheadline)
    /// Mirrors `.subheadline.weight(.semibold)` (also standing in for
    /// `.weight(.medium)`/`.weight(.bold)` at this size -- see file header).
    /// Row titles, list item titles, choice-chip labels.
    static let action = Font.custom(semibold, size: 15, relativeTo: .subheadline)

    // MARK: Footnote

    /// Mirrors plain `.footnote` (13pt regular).
    static let footnote = Font.custom(regular, size: 13, relativeTo: .footnote)
    /// Mirrors `.footnote.weight(.semibold)` (also standing in for
    /// `.weight(.medium)` at this size). Also used for monospaced metrics
    /// (counts, durations) via `.metric.monospacedDigit()`.
    static let metric = Font.custom(semibold, size: 13, relativeTo: .footnote)

    // MARK: Caption

    /// Mirrors plain `.caption` (12pt regular).
    static let caption = Font.custom(regular, size: 12, relativeTo: .caption)
    /// Mirrors `.caption.weight(.semibold)` (also standing in for
    /// `.weight(.bold)`/`.bold()` at this size -- see file header).
    /// `.weight(.semibold)` chained onto `.caption` doesn't reliably resolve
    /// against a custom static face -- Pretendard-SemiBold's family name
    /// ("Pretendard SemiBold") differs from Pretendard-Regular's ("Pretendard"),
    /// so weight-based face lookup within .caption's family wouldn't find it.
    static let captionEmphasis = Font.custom(semibold, size: 12, relativeTo: .caption)

    // MARK: Caption2 (smallest -- badges, timestamps, dense metadata)

    /// Mirrors plain `.caption2` (11pt regular).
    static let caption2 = Font.custom(regular, size: 11, relativeTo: .caption2)
    /// Mirrors `.caption2.weight(.semibold)` (also standing in for
    /// `.weight(.medium)`/`.bold()` at this size).
    static let caption2Emphasis = Font.custom(semibold, size: 11, relativeTo: .caption2)

    // MARK: Titles

    /// Mirrors plain `.title3` (20pt regular).
    static let title3 = Font.custom(regular, size: 20, relativeTo: .title3)
    /// Mirrors `.title3.weight(.bold)` (20pt) -- editorial/article-style
    /// headlines (news briefing lead story, etc).
    static let editorialTitle = Font.custom(bold, size: 20, relativeTo: .title3)
    /// Mirrors plain `.title2` (22pt regular).
    static let title2 = Font.custom(regular, size: 22, relativeTo: .title2)
    /// Mirrors `.title2.weight(.bold)`/`.bold()` (22pt) -- detail-screen
    /// titles (article detail, schedule detail).
    static let detailTitle = Font.custom(bold, size: 22, relativeTo: .title2)
    /// Same size/weight as `detailTitle` -- kept as a separate token because
    /// it names a specific role (the "Memdo" wordmark), not a text style, so
    /// call sites read as "the brand mark" rather than "a bold title that
    /// happens to be the logo."
    static let brand = Font.custom(bold, size: 22, relativeTo: .title2)
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
        cornerRadius: CGFloat = MemdoMetrics.fieldRadius,
        interactive: Bool = true
    ) -> some View {
        if #available(iOS 26.0, *) {
            // .interactive() adds continuous touch-response glass morphing --
            // fine (and wanted) for plain pressable buttons, but wrapping a
            // live TextField (search field, Agent composer) forced a glass
            // recompute on every keystroke, producing visible typing lag and
            // "glassEffect() tried to update multiple times per frame"
            // warnings (found during founder dogfooding). Those two call
            // sites now pass interactive: false; every other caller keeps
            // the original touch-response morph.
            glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: cornerRadius))
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
