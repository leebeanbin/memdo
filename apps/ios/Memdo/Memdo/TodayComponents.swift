import SafariServices
import SwiftUI

struct TodayHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let eyebrow: String
    let title: String
    let subtitle: String
    let completedCount: Int
    let totalCount: Int
    let onOpenSummary: () -> Void
    let onOpenGuide: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    titleGroup
                    HStack {
                        Spacer()
                        guideButton
                        progressButton
                    }
                }
            } else {
                HStack(alignment: .top) {
                    titleGroup
                    Spacer()
                    guideButton
                    progressButton
                }
            }
        }
    }

    private var guideButton: some View {
        Button(action: onOpenGuide) {
            Image(systemName: "questionmark.circle")
                .font(MemdoTypography.title3)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(width: 40, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Memdo 시작 가이드")
    }

    private var titleGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(MemdoTypography.captionEmphasis)
                    .foregroundStyle(MemdoTheme.brand)
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(MemdoTheme.ink)
                Text(subtitle)
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.secondaryInk)
        }
    }

    private var progressButton: some View {
        Button(action: onOpenSummary) {
            ZStack {
                    Circle()
                        .stroke(MemdoTheme.accent.opacity(0.16), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: totalCount == 0 ? 0 : CGFloat(completedCount) / CGFloat(totalCount))
                        .stroke(MemdoTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(completedCount)/\(totalCount)")
                            .font(MemdoTypography.metric.monospacedDigit())
                        Text("완료")
                            .font(MemdoTypography.caption2Emphasis)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                    }
            }
            .dynamicTypeSize(.small ... .large)
            .frame(width: 48, height: 48)
            .foregroundStyle(MemdoTheme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("오늘 완료 현황")
        .accessibilityValue("\(totalCount)개 중 \(completedCount)개 완료")
    }
}

struct TodayWeekIndex: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let dates: [Date]
    let selectedDate: Date
    let scheduleCounts: [Date: Int]
    let onSelect: (Date) -> Void
    let onAdd: (Date) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(dates, id: \.self) { date in
                            dateButton(date)
                                .frame(width: 64)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                HStack(spacing: 4) {
                    ForEach(dates, id: \.self) { date in
                        dateButton(date)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func dateButton(_ date: Date) -> some View {
        let count = scheduleCounts[date, default: 0]
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)

        return Button { onSelect(date) } label: {
                    VStack(spacing: 4) {
                        Text(date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ko_KR"))))
                            .font(MemdoTypography.captionEmphasis)
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(MemdoTypography.action.monospacedDigit())
                        MemdoScheduleCountDots(
                            count: count,
                            isEmphasized: isSelected
                        )
                    }
                    .foregroundStyle(isSelected ? MemdoTheme.onAccent : MemdoTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(isSelected ? MemdoTheme.accent : Color.clear)
                    .clipShape(Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        date.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR")))
                    )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in onAdd(date) }
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue("\(count)개\(isSelected ? ", 선택됨" : "")")
        .accessibilityHint("길게 누르면 이 날짜에 일정을 추가합니다")
        .accessibilityAction(named: "새 일정 추가") { onAdd(date) }
    }
}

struct TodayIntentionPrompt: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isToday: Bool
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("오늘의 방향", systemImage: "sparkle")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                    Text(isToday ? "오늘은 어떤 하루를 보내고 싶나요?" : "이날에는 어떤 시간을 보내고 싶나요?")
                        .font(MemdoTypography.sectionTitle)
                        .foregroundStyle(MemdoTheme.ink)
                    Text("계획이 비어 있을 때 가볍게 시작해보세요")
                        .font(MemdoTypography.subtitle)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "plus")
                        .font(MemdoTypography.action)
                        .foregroundStyle(MemdoTheme.brand)
                        .frame(width: 36, height: 36)
                        .background(MemdoTheme.brandSoft, in: Circle())
                }
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .background(
                MemdoTheme.surface,
                in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                    .stroke(MemdoTheme.outline, lineWidth: 0.5)
            }
        }
        .buttonStyle(MemdoScaleButtonStyle())
    }
}

private struct MemdoScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct TodayScheduleSection: View {
    let schedules: [ScheduleDetail]
    let isExpanded: Bool
    let onAdd: () -> Void
    let onToggleExpanded: () -> Void
    let onOpenSchedule: (ScheduleDetail) -> Void
    let onToggleDone: (ScheduleDetail) -> Void

    private var visibleSchedules: [ScheduleDetail] {
        Array(schedules.prefix(isExpanded ? schedules.count : 3))
    }

    var body: some View {
        MemdoSection(
            title: "일정",
            actionIcon: "plus",
            actionLabel: "새 일정 추가",
            action: onAdd
        ) {
            VStack(spacing: 0) {
                ForEach(visibleSchedules) { schedule in
                    ScheduleRow(
                        schedule: schedule,
                        context: .timeline,
                        onOpen: { onOpenSchedule(schedule) },
                        onToggleDone: { onToggleDone(schedule) }
                    )
                    if schedule.id != visibleSchedules.last?.id {
                        Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                    }
                }

                if schedules.count > 3 {
                    Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                    MemdoDisclosureRow(
                        isExpanded: isExpanded,
                        hiddenCount: schedules.count - 3,
                        totalCount: schedules.count,
                        action: onToggleExpanded
                    )
                }
            }
            .memdoRowGroup()
        }
    }
}

struct TodayBriefingSection: View {
    @State private var items: [BriefingRepository.FetchedItem] = []
    /// The full fetch (up to 20 items across every category), kept
    /// separately from `items` (the 5 curated for the sheet's visible list)
    /// so BriefingTopicView has more than 1-3 items to filter down to when
    /// browsing a single category -- `items` alone was too thin a pool for
    /// "먼저 살펴보고" (browse first) to mean anything.
    @State private var topicPool: [BriefingRepository.FetchedItem] = []
    @State private var isLoading = false
    @State private var aiSummary: String?
    @State private var showsBriefing = false
    @State private var selectedCategories: Set<BriefingFeedCategory> = Self.storedCategories()

    private static func storedCategories() -> Set<BriefingFeedCategory> {
        (UserDefaults.standard.stringArray(forKey: "briefing-selected-categories") ?? [])
            .reduce(into: []) { result, rawValue in
                if let category = BriefingFeedCategory(rawValue: rawValue) {
                    result.insert(category)
                }
            }
    }

    var body: some View {
        MemdoSection(
            title: "오늘의 브리핑",
            trailing: isLoading && items.isEmpty ? "업데이트 중" : nil
        ) {
            if isLoading && items.isEmpty {
                BriefingLoadingRow()
            } else if items.isEmpty {
                MemdoStatusRow(
                    title: "브리핑을 준비하지 못했어요",
                    systemImage: "newspaper",
                    detail: "잠시 후 최신 뉴스를 다시 확인해주세요.",
                    tint: MemdoTheme.secondaryInk
                )
            } else {
                BriefingPreview(
                    summary: aiSummary,
                    item: items[0],
                    count: min(items.count, 5),
                    onTap: { showsBriefing = true }
                )
            }
        }
        .sheet(isPresented: $showsBriefing) {
            BriefingSheet(
                items: Array(items.prefix(5)),
                topicPool: topicPool,
                summary: aiSummary,
                selectedCategories: $selectedCategories
            )
            .memdoSheetPresentation([.large])
        }
        .task(id: briefingTaskID) { await loadBriefing() }
        .onChange(of: selectedCategories) { _, categories in
            UserDefaults.standard.set(
                categories.map(\.rawValue).sorted(),
                forKey: "briefing-selected-categories"
            )
        }
    }

    private var briefingTaskID: String {
        selectedCategories.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func loadBriefing() async {
        isLoading = true
        let fetched = await BriefingRepository.shared.fetchWithCache(
            categories: BriefingFeedCategory.allCases,
            keywords: []
        )
        let curated = Self.curatedItems(fetched, selectedCategories: selectedCategories)
        items = curated
        topicPool = fetched
        isLoading = false

        if #available(iOS 26, *) {
            aiSummary = await BriefingRepository.shared.summarize(
                items: curated,
                categories: selectedCategories.isEmpty
                    ? BriefingFeedCategory.allCases
                    : BriefingFeedCategory.allCases.filter(selectedCategories.contains),
                keywords: []
            )
        } else {
            aiSummary = nil
        }
    }

    static func curatedItems(
        _ items: [BriefingRepository.FetchedItem],
        selectedCategories: Set<BriefingFeedCategory>,
        limit: Int = 5
    ) -> [BriefingRepository.FetchedItem] {
        guard limit > 0 else { return [] }

        var result = selectedCategories.isEmpty
            ? []
            : Array(items.filter { selectedCategories.contains($0.category) }.prefix(min(3, limit)))
        var usedIDs = Set(result.map(\.id))
        var representedCategories = Set(result.map(\.category))

        for item in items where result.count < limit {
            guard !usedIDs.contains(item.id), !representedCategories.contains(item.category) else { continue }
            result.append(item)
            usedIDs.insert(item.id)
            representedCategories.insert(item.category)
        }

        for item in items where result.count < limit {
            guard usedIDs.insert(item.id).inserted else { continue }
            result.append(item)
        }

        return result
    }
}

private struct BriefingLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct BriefingPreview: View {
    let summary: String?
    let item: BriefingRepository.FetchedItem
    let count: Int
    let onTap: () -> Void

    private var previewText: String {
        summary?.compactBriefingText ?? item.title
    }

    private var metadata: String {
        "\(count)개 · 약 3분"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("오늘 꼭 알아둘 변화")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                    Text(previewText)
                        .font(MemdoTypography.sectionTitle)
                        .foregroundStyle(MemdoTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 8) {
                    Text("\(item.sourceName) · \(metadata)")
                        .font(MemdoTypography.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, MemdoMetrics.rowInset)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MemdoScaleButtonStyle())
        .memdoRowGroup()
        .accessibilityLabel("오늘의 브리핑 \(count)개. \(previewText)")
        .accessibilityHint("전체 브리핑을 엽니다")
    }
}

private struct BriefingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [BriefingRepository.FetchedItem]
    /// Passed to BriefingLeadStory/BriefingNewsRow as `relatedItems` instead
    /// of `items` -- the full fetch, not just the 5 curated for this sheet's
    /// visible list, so BriefingTopicView has a real pool to filter by
    /// category from. `items` stays what's actually rendered here.
    let topicPool: [BriefingRepository.FetchedItem]
    let summary: String?
    @Binding var selectedCategories: Set<BriefingFeedCategory>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            Date.now.formatted(
                                .dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR"))
                            )
                        )
                            .font(MemdoTypography.captionEmphasis)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                        Text("오늘 꼭 알아둘 \(items.count)개")
                            .font(MemdoTypography.editorialTitle)
                            .foregroundStyle(MemdoTheme.ink)
                        Text("분야를 고르지 않아도 새로운 이야기를 먼저 보여드려요.")
                            .font(MemdoTypography.subtitle)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                    }
                    .padding(.horizontal, MemdoMetrics.pagePadding)

                    if let summary {
                        HStack(alignment: .top, spacing: 10) {
                            Rectangle()
                                .fill(MemdoTheme.brand)
                                .frame(width: 3)
                            Text(summary.compactBriefingText)
                                .font(MemdoTypography.action)
                                .foregroundStyle(MemdoTheme.ink)
                        }
                        .padding(.horizontal, MemdoMetrics.pagePadding)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("오늘의 흐름, \(summary.compactBriefingText)")
                    }

                    // One row group, not a card plus a separate list -- DESIGN.md
                    // 5.8: "반복 항목은 카드 여러 개가 아니라 하나의 그룹 안에
                    // 행으로 배치하며 카드 안에 카드를 넣지 않는다", and the
                    // surface-card treatment is reserved for the empty-state
                    // intention prompt specifically, not for content rows.
                    if !items.isEmpty {
                        VStack(spacing: 0) {
                            if let lead = items.first {
                                BriefingLeadStory(
                                    item: lead,
                                    relatedItems: topicPool,
                                    selectedCategories: $selectedCategories
                                )
                                if items.count > 1 {
                                    Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                                }
                            }
                            ForEach(Array(items.dropFirst().enumerated()), id: \.element.id) { index, item in
                                BriefingNewsRow(
                                    number: index + 2,
                                    item: item,
                                    relatedItems: topicPool,
                                    selectedCategories: $selectedCategories
                                )
                                if item.id != items.last?.id {
                                    Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                                }
                            }
                        }
                        .memdoRowGroup()
                        .padding(.horizontal, MemdoMetrics.pagePadding)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(MemdoTheme.background)
            .navigationTitle("오늘의 브리핑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}

/// Colored circle for a briefing category -- an icon variant for the lead
/// story (where the category is the only label, no ordinal) and a
/// number-in-circle variant for list rows (where read-order still matters).
/// Reuses ScheduleColor rather than inventing a second palette -- see
/// BriefingFeedCategory.accentColor.
/// Same shape/size as ScheduleSourceIcon (ScheduleRow.swift) -- rounded
/// square at MemdoMetrics.iconRadius, not a circle. That's the app's one
/// existing "icon in a tinted badge" convention (icon color = the item's
/// ScheduleColor, background = its soft variant); these badges match it
/// exactly rather than introducing a second badge shape.
private struct BriefingCategoryBadge: View {
    let category: BriefingFeedCategory

    var body: some View {
        Image(systemName: category.systemImage)
            .font(MemdoTypography.captionEmphasis)
            .foregroundStyle(category.accentColor.swiftUIColor)
            .frame(width: 30, height: 30)
            .background(
                category.accentColor.softSwiftUIColor,
                in: RoundedRectangle(cornerRadius: MemdoMetrics.iconRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

private struct BriefingOrdinalBadge: View {
    let number: Int
    let category: BriefingFeedCategory

    var body: some View {
        Text(String(format: "%02d", number))
            .font(MemdoTypography.metric.monospacedDigit())
            .foregroundStyle(category.accentColor.swiftUIColor)
            .frame(width: 30, height: 30)
            .background(
                category.accentColor.softSwiftUIColor,
                in: RoundedRectangle(cornerRadius: MemdoMetrics.iconRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

private struct BriefingLeadStory: View {
    let item: BriefingRepository.FetchedItem
    let relatedItems: [BriefingRepository.FetchedItem]
    @Binding var selectedCategories: Set<BriefingFeedCategory>

    var body: some View {
        NavigationLink {
            BriefingStoryDetail(
                item: item,
                relatedItems: relatedItems,
                selectedCategories: $selectedCategories
            )
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    BriefingCategoryBadge(category: item.category)
                    Text(item.category.rawValue)
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(item.category.accentColor.swiftUIColor)
                }
                Text(item.title)
                    .font(MemdoTypography.editorialTitle)
                    .foregroundStyle(MemdoTheme.ink)
                    .lineSpacing(4)
                    .lineLimit(3)
                if !item.summary.isEmpty {
                    Text(item.summary.compactBriefingText)
                        .font(MemdoTypography.subtitle)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .lineSpacing(3)
                        .lineLimit(2)
                }
                Text(item.metadata)
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, MemdoMetrics.rowInset)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MemdoScaleButtonStyle())
        .accessibilityLabel("첫 번째 기사, \(item.title), \(item.metadata)")
        .accessibilityHint("기사 요약과 관련 주제를 엽니다")
    }
}

private extension String {
    /// RSS description fields from Korean news aggregators are commonly a
    /// list of unpunctuated clause fragments, one per line ("A안 찬성 47%\n
    /// B는 반대\n..."), not full sentences. Replacing "\n" with a bare space
    /// (the old behavior) ran them together into a single unpunctuated wall
    /// of text -- e.g. "...47.4% 반대 41.9%보다 다소 높아 2030은 반대 55%
    /// 넘어서 이준석 "당사자 빠진 설계"여성도..." with no marker between
    /// distinct points. Joins with " · " instead -- the same separator this
    /// app already uses everywhere else for "several distinct facts on one
    /// line" (e.g. "매일경제 · 5개 · 약 3분"), so a multi-clause summary
    /// reads the same way the rest of the UI already presents grouped facts.
    var compactBriefingText: String {
        let cleaned = replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "* ", with: "")
        let clauses = cleaned
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return clauses
            .joined(separator: " · ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".。"))
    }
}

// MARK: - Briefing News Row (RSS feed items)

private struct BriefingLoadingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.85)
            Text("최신 뉴스를 가져오는 중...")
                .font(MemdoTypography.subtitle)
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MemdoMetrics.rowInset)
        .frame(minHeight: 56)
    }
}

private struct BriefingNewsRow: View {
    let number: Int
    let item: BriefingRepository.FetchedItem
    let relatedItems: [BriefingRepository.FetchedItem]
    @Binding var selectedCategories: Set<BriefingFeedCategory>

    var body: some View {
        NavigationLink {
            BriefingStoryDetail(
                item: item,
                relatedItems: relatedItems,
                selectedCategories: $selectedCategories
            )
        } label: {
            HStack(alignment: .top, spacing: MemdoMetrics.rowSpacing) {
                BriefingOrdinalBadge(number: number, category: item.category)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(MemdoTypography.action)
                        .foregroundStyle(MemdoTheme.ink)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(item.metadata)
                        .font(MemdoTypography.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .lineLimit(1)
                }
                .padding(.top, 3)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(MemdoTypography.caption2Emphasis)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .padding(.top, 6)
            }
            .padding(.horizontal, MemdoMetrics.rowInset)
            .padding(.vertical, 14)
            .frame(minHeight: MemdoMetrics.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(MemdoScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number)번째 기사, \(item.title), \(item.metadata)")
        .accessibilityHint("기사 요약과 관련 주제를 엽니다")
    }
}

private struct BriefingStoryDetail: View {
    @State private var safariItem: BriefingLink?
    let item: BriefingRepository.FetchedItem
    let relatedItems: [BriefingRepository.FetchedItem]
    @Binding var selectedCategories: Set<BriefingFeedCategory>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        BriefingCategoryBadge(category: item.category)
                        Text(item.category.rawValue)
                            .font(MemdoTypography.captionEmphasis)
                            .foregroundStyle(item.category.accentColor.swiftUIColor)
                    }
                    Text(item.title)
                        .font(MemdoTypography.detailTitle)
                        .foregroundStyle(MemdoTheme.ink)
                        .lineSpacing(5)
                    Text(item.metadata)
                        .font(MemdoTypography.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                if !item.summary.isEmpty {
                    VStack(alignment: .leading, spacing: MemdoMetrics.sectionContentSpacing) {
                        Text("핵심 내용")
                            .font(MemdoTypography.sectionTitle)
                        Text(item.summary.compactBriefingText)
                            .font(MemdoTypography.body)
                            .foregroundStyle(MemdoTheme.ink)
                            .lineSpacing(5)
                    }
                    .padding(.vertical, 18)
                    .memdoRowGroup()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("이 이야기의 주제")
                        .font(MemdoTypography.sectionTitle)

                    NavigationLink {
                        BriefingTopicView(
                            category: item.category,
                            items: relatedItems.filter { $0.category == item.category },
                            selectedCategories: $selectedCategories
                        )
                    } label: {
                        HStack(spacing: 12) {
                            BriefingCategoryBadge(category: item.category)
                            Text(item.category.rawValue)
                                .font(MemdoTypography.action)
                            Spacer()
                            if selectedCategories.contains(item.category) {
                                Label("관심", systemImage: "checkmark")
                                    .font(MemdoTypography.captionEmphasis)
                                    .foregroundStyle(MemdoTheme.secondaryInk)
                            }
                            Image(systemName: "chevron.right")
                                .font(MemdoTypography.captionEmphasis)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(MemdoTheme.ink)
                        .frame(minHeight: MemdoMetrics.settingsRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MemdoScaleButtonStyle())
                    .memdoRowGroup()
                    .accessibilityHint("관련 기사를 살펴보고 관심사에 추가할 수 있습니다")
                }

                if item.url != nil {
                    Button("원문 읽기") {
                        if let url = item.url { safariItem = BriefingLink(url: url) }
                    }
                    .buttonStyle(MemdoPrimaryActionButtonStyle())
                }
            }
            .padding(.horizontal, MemdoMetrics.pagePadding)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(MemdoTheme.background)
        .navigationTitle("기사")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $safariItem) { link in
            BriefingSafariView(url: link.url).ignoresSafeArea()
        }
    }
}

private struct BriefingTopicView: View {
    @State private var safariItem: BriefingLink?
    let category: BriefingFeedCategory
    let items: [BriefingRepository.FetchedItem]
    @Binding var selectedCategories: Set<BriefingFeedCategory>

    private var isSelected: Bool { selectedCategories.contains(category) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: category.systemImage)
                        .font(MemdoTypography.title3)
                        .foregroundStyle(category.accentColor.swiftUIColor)
                        .frame(width: 44, height: 44)
                        .background(category.accentColor.softSwiftUIColor, in: Circle())
                        .accessibilityHidden(true)
                    Text(category.rawValue)
                        .font(MemdoTypography.detailTitle)
                    Text("관련 기사 \(items.count)개를 먼저 살펴보고 관심사에 추가할 수 있어요.")
                        .font(MemdoTypography.subtitle)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                if isSelected {
                    Button {
                        selectedCategories.remove(category)
                    } label: {
                        Label("관심사에서 제거", systemImage: "checkmark")
                    }
                    .buttonStyle(MemdoSecondaryActionButtonStyle())
                    .accessibilityAddTraits(.isSelected)
                } else {
                    Button {
                        selectedCategories.insert(category)
                    } label: {
                        Label("관심사에 추가", systemImage: "plus")
                    }
                    .buttonStyle(MemdoPrimaryActionButtonStyle())
                }

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            if let url = item.url { safariItem = BriefingLink(url: url) }
                        } label: {
                            HStack(alignment: .top, spacing: MemdoMetrics.rowSpacing) {
                                BriefingOrdinalBadge(number: index + 1, category: item.category)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title)
                                        .font(MemdoTypography.action)
                                        .foregroundStyle(MemdoTheme.ink)
                                        .lineSpacing(3)
                                        .lineLimit(2)
                                    Text(item.metadata)
                                        .font(MemdoTypography.caption)
                                        .foregroundStyle(MemdoTheme.secondaryInk)
                                }
                                .padding(.top, 3)
                                Spacer(minLength: 8)
                            }
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MemdoScaleButtonStyle())
                        .disabled(item.url == nil)

                        if item.id != items.last?.id {
                            Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                        }
                    }
                }
                .memdoRowGroup()
            }
            .padding(.horizontal, MemdoMetrics.pagePadding)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(MemdoTheme.background)
        .navigationTitle("주제")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $safariItem) { link in
            BriefingSafariView(url: link.url).ignoresSafeArea()
        }
    }
}

private extension BriefingRepository.FetchedItem {
    var metadata: String {
        [sourceName, relativeTime, category.rawValue]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - In-app browser

struct BriefingSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(MemdoTheme.brand)
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
