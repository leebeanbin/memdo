import SwiftUI

struct MemdoPage<Content: View>: View {
    let title: String
    let subtitle: String
    let eyebrow: String
    let headerActionIcon: String?
    let headerActionLabel: String
    let headerAction: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        eyebrow: String,
        headerActionIcon: String? = nil,
        headerActionLabel: String = "",
        headerAction: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.headerActionIcon = headerActionIcon
        self.headerActionLabel = headerActionLabel
        self.headerAction = headerAction
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MemdoPageBackground()
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
                    .padding(.bottom, MemdoMetrics.tabBarClearance)
                }
                .scrollIndicators(.hidden)
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
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .foregroundStyle(MemdoTheme.brand)
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(MemdoTheme.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionIcon {
            Button(action: action) {
                MemdoIconButtonLabel(systemImage: actionIcon)
            }
            .buttonStyle(.plain)
            .memdoFloatingSurface(radius: 22)
            .accessibilityLabel(actionLabel)
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
            .font(.headline)
            .foregroundStyle(MemdoTheme.ink)
    }

    @ViewBuilder
    private var trailingText: some View {
        if let trailing {
            Text(trailing)
                .font(.caption.bold())
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionIcon {
            Button(action: action) {
                MemdoIconButtonLabel(systemImage: actionIcon)
                    .font(.caption.weight(.semibold))
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
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
                .font(.caption.bold())
                .foregroundStyle(isSelected ? MemdoTheme.onAccent : MemdoTheme.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: MemdoMetrics.touchTarget)
                .background(isSelected ? MemdoTheme.accent : MemdoTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : MemdoTheme.controlOutline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
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
                    systemImage: isExpanded ? "chevron.up" : "ellipsis"
                )
                Text("총 \(totalCount)개")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            }
            .font(.subheadline.weight(.semibold))
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
