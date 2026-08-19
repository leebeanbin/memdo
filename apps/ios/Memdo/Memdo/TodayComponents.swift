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
                .font(.title3)
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
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MemdoTheme.brand)
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(MemdoTheme.ink)
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
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
                            .font(.caption.weight(.bold))
                        Text("완료")
                            .font(.caption2.weight(.semibold))
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
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.subheadline.weight(.semibold))
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
                    .accessibilityLabel(date.formatted(.dateTime.month().day().weekday(.wide)))
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
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MemdoTheme.brand)
                    Text(isToday ? "오늘은 어떤 하루를 보내고 싶나요?" : "이날에는 어떤 시간을 보내고 싶나요?")
                        .font(.headline)
                        .foregroundStyle(MemdoTheme.ink)
                    Text("계획이 비어 있을 때 가볍게 시작해보세요")
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
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
    @State private var isLoading = false
    @State private var aiSummary: String?
    @State private var showsBriefing = false
    // Seeded from UserDefaults and kept in sync via didChangeNotification so
    // interest edits in Settings show up here without an app relaunch.
    @State private var selectedCategories: [BriefingFeedCategory] = Self.storedCategories()
    @State private var selectedKeywords: [String] = Self.storedKeywords()

    private static func storedCategories() -> [BriefingFeedCategory] {
        (UserDefaults.standard.stringArray(forKey: "briefing-selected-categories") ?? [])
            .compactMap { BriefingFeedCategory(rawValue: $0) }
    }

    private static func storedKeywords() -> [String] {
        UserDefaults.standard.stringArray(forKey: "briefing-selected-keywords") ?? []
    }

    private var isEnabled: Bool { !selectedCategories.isEmpty || !selectedKeywords.isEmpty }

    var body: some View {
        Group {
            if isEnabled {
                MemdoSection(
                    title: "오늘의 브리핑",
                    trailing: isLoading && items.isEmpty ? "업데이트 중" : nil
                ) {
                    if isLoading && items.isEmpty {
                        BriefingLoadingRow()
                    } else if items.isEmpty {
                        MemdoStatusRow(
                            title: "불러온 기사가 없어요",
                            systemImage: "newspaper",
                            detail: "관심 분야와 키워드를 확인해주세요.",
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
                    BriefingSheet(items: Array(items.prefix(5)), summary: aiSummary)
                        .memdoSheetPresentation([.medium, .large])
                }
            }
        }
        .task(id: briefingTaskID) { await loadBriefing() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let categories = Self.storedCategories()
            let keywords = Self.storedKeywords()
            if categories != selectedCategories { selectedCategories = categories }
            if keywords != selectedKeywords { selectedKeywords = keywords }
        }
    }

    // Re-runs the fetch whenever interests change (task(id:) cancels the old one).
    private var briefingTaskID: String {
        selectedCategories.map(\.rawValue).joined(separator: ",")
            + "|" + selectedKeywords.joined(separator: ",")
    }

    private func loadBriefing() async {
        guard isEnabled else {
            items = []
            aiSummary = nil
            return
        }
        isLoading = true
        let cats = selectedCategories
        let kws  = selectedKeywords
        let fetched = await BriefingRepository.shared.fetchWithCache(categories: cats, keywords: kws)
        items = fetched
        isLoading = false

        // AI summary runs after articles are visible (returns instantly from cache if same day)
        if #available(iOS 26, *) {
            aiSummary = await BriefingRepository.shared.summarize(
                items: fetched, categories: cats, keywords: kws
            )
        }
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
        count > 1 ? "\(item.sourceName) 외 \(count - 1)개 · 1분" : "\(item.sourceName) · 1분"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("AI 요약", systemImage: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MemdoTheme.brand)
                    Text(previewText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(MemdoTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 8) {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
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
    @State private var safariItem: BriefingLink?
    let items: [BriefingRepository.FetchedItem]
    let summary: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let summary {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("AI 요약", systemImage: "sparkles")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MemdoTheme.brand)
                            Text(summary.compactBriefingText)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(MemdoTheme.ink)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, MemdoMetrics.pagePadding)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("기사 \(items.count)개")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, MemdoMetrics.pagePadding)

                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                BriefingNewsRow(item: item) {
                                    if let url = item.url { safariItem = BriefingLink(url: url) }
                                }
                                if index < items.count - 1 {
                                    Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                                }
                            }
                        }
                        .memdoRowGroup()
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
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
        .sheet(item: $safariItem) { link in
            BriefingSafariView(url: link.url).ignoresSafeArea()
        }
    }
}

private extension String {
    var compactBriefingText: String {
        replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "* ", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".。"))
    }
}

// MARK: - Briefing News Row (RSS feed items)

private struct BriefingLoadingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.85)
            Text("최신 뉴스를 가져오는 중...")
                .font(.subheadline)
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MemdoMetrics.rowInset)
        .frame(minHeight: 56)
    }
}

private struct BriefingNewsRow: View {
    let item: BriefingRepository.FetchedItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MemdoMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MemdoTheme.ink)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    Text(metadata)
                        .font(.caption2)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .padding(.horizontal, MemdoMetrics.rowInset)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.category.rawValue), \(item.sourceName), \(item.title)")
        .accessibilityHint("탭하면 원문을 열어요")
    }

    private var metadata: String {
        [item.sourceName, item.relativeTime, item.matchedKeyword ?? item.category.rawValue]
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
