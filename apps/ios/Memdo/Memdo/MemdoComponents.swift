import SwiftUI

struct MemdoBrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image("MemdoMark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(MemdoTheme.ink)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct MemdoPage<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let subtitle: String
    let eyebrow: String
    let headerActionIcon: String?
    let headerActionLabel: String
    let headerAction: () -> Void
    let bottomClearance: CGFloat
    let scrollTarget: CoachMarkTarget?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        eyebrow: String,
        headerActionIcon: String? = nil,
        headerActionLabel: String = "",
        headerAction: @escaping () -> Void = {},
        bottomClearance: CGFloat = MemdoMetrics.tabBarClearance,
        scrollTarget: CoachMarkTarget? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.headerActionIcon = headerActionIcon
        self.headerActionLabel = headerActionLabel
        self.headerAction = headerAction
        self.bottomClearance = bottomClearance
        self.scrollTarget = scrollTarget
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MemdoPageBackground()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
                            MemdoPageHeader(
                                title: title,
                                subtitle: subtitle,
                                eyebrow: eyebrow,
                                actionIcon: headerActionIcon,
                                actionLabel: headerActionLabel,
                                action: headerAction
                            )
                            content
                        }
                        .padding(MemdoMetrics.pagePadding)
                        .padding(.bottom, bottomClearance)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: scrollTarget, initial: true) { _, target in
                        guard let target else { return }
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(MemdoTheme.accent)
    }
}

struct MemdoPageHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let subtitle: String
    let eyebrow: String
    var actionIcon: String?
    var actionLabel = ""
    var action: () -> Void = {}

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize, actionIcon != nil {
                VStack(alignment: .leading, spacing: 12) {
                    titleGroup
                    HStack {
                        Spacer()
                        actionButton
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    titleGroup
                    Spacer(minLength: 8)
                    actionButton
                }
            }
        }
    }

    private var titleGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !eyebrow.isEmpty {
                Text(eyebrow)
                    .font(MemdoTypography.captionEmphasis)
                    .foregroundStyle(MemdoTheme.brandInk)
            }
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(MemdoTheme.ink)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(MemdoTypography.subtitle)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionIcon {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    MemdoIconButtonLabel(systemImage: actionIcon)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(actionLabel)
            } else {
                Button(action: action) {
                    MemdoIconButtonLabel(systemImage: actionIcon)
                }
                .buttonStyle(.plain)
                .memdoFloatingSurface(cornerRadius: MemdoMetrics.groupRadius)
                .accessibilityLabel(actionLabel)
            }
        }
    }

}

struct MemdoSection<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let trailing: String?
    let actionIcon: String?
    let actionLabel: String
    let action: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        trailing: String? = nil,
        actionIcon: String? = nil,
        actionLabel: String = "",
        action: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.actionIcon = actionIcon
        self.actionLabel = actionLabel
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MemdoMetrics.sectionContentSpacing) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle
                        trailingText
                    }
                    Spacer()
                    actionButton
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle
                    Spacer()
                    trailingText
                    actionButton
                }
            }
            content
        }
    }

    private var sectionTitle: some View {
        Text(title)
            .font(MemdoTypography.sectionTitle)
            .foregroundStyle(MemdoTheme.ink)
    }

    @ViewBuilder
    private var trailingText: some View {
        if let trailing {
            Text(trailing)
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionIcon {
            Button(action: action) {
                MemdoIconButtonLabel(systemImage: actionIcon)
                    .font(MemdoTypography.captionEmphasis)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionLabel)
        }
    }
}

struct MemdoIconButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
    }
}

struct MemdoPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MemdoTypography.buttonLabel)
            .lineLimit(1)
            .foregroundStyle(MemdoTheme.onBrand)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
            .background(
                MemdoTheme.brand,
                in: RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

struct MemdoSecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MemdoTypography.buttonLabel)
            .lineLimit(1)
            .foregroundStyle(MemdoTheme.secondaryInk)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
            .background(
                MemdoTheme.accentSoft,
                in: RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

struct MemdoDestructiveActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MemdoTypography.buttonLabel)
            .lineLimit(1)
            .foregroundStyle(MemdoTheme.onDestructive)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
            .background(
                MemdoTheme.destructive,
                in: RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

struct MemdoIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MemdoTheme.ink)
            .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
    }
}

/// Unified color-swatch picker button (fd7) -- replaces three near-identical
/// 22/26/30pt gesture-only implementations (`.onTapGesture`, not a real
/// `Button`) in ScheduleSheets.swift. Always a real 44pt tap target
/// regardless of the visible swatch's own size, matching every other
/// interactive control in this app; `action` lets each call site keep its
/// own tap semantics (some toggle back to nil on re-tap, one always sets).
struct MemdoColorSwatch: View {
    let color: ScheduleColor
    let isSelected: Bool
    var swatchSize: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: swatchSize, height: swatchSize)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: swatchSize * 0.46, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                }
            }
            .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct MemdoScheduleCountDots: View {
    let count: Int
    let isEmphasized: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(count, 3), id: \.self) { _ in
                Circle()
                    .fill(isEmphasized ? MemdoTheme.onAccent : MemdoTheme.brand)
                    .frame(width: 3, height: 3)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

struct MemdoChoiceButton: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
            }
                .font(MemdoTypography.action)
                .foregroundStyle(isSelected ? MemdoTheme.onAccent : MemdoTheme.ink)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(isSelected ? MemdoTheme.accent : MemdoTheme.accentSoft, in: Capsule())
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
    }
}

struct MemdoStatusRow: View {
    let title: String
    let systemImage: String
    var detail: String?
    var tint = MemdoTheme.secondaryInk

    var body: some View {
        HStack(spacing: MemdoMetrics.rowSpacing) {
            Image(systemName: systemImage)
                .font(MemdoTypography.action)
                .foregroundStyle(tint)
                .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(MemdoTypography.action)
                if let detail {
                    Text(detail)
                        .font(MemdoTypography.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MemdoMetrics.rowInset)
        .padding(.vertical, 4)
        .memdoRowGroup()
        .accessibilityElement(children: .combine)
    }
}

struct MemdoDisclosureRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isExpanded: Bool
    let hiddenCount: Int
    let totalCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            disclosureLayout {
                Label(
                    isExpanded ? "일정 접기" : "나머지 \(hiddenCount)개 보기",
                    systemImage: isExpanded ? "chevron.up" : "chevron.down"
                )
                Text("총 \(totalCount)개")
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            }
            .font(MemdoTypography.action)
            .foregroundStyle(MemdoTheme.accent)
            .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "일정 목록을 세 개로 줄입니다" : "나머지 일정을 이어서 보여줍니다")
    }

    private var disclosureLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
    }
}

extension View {
    func memdoSheetPresentation(
        _ detents: Set<PresentationDetent> = [.medium, .large]
    ) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(MemdoTheme.background)
    }
}
