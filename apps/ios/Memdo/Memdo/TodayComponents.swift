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
    @State private var selectedURL: URL?
    @State private var showSafari = false

    private var selectedCategories: [BriefingFeedCategory] {
        (UserDefaults.standard.stringArray(forKey: "briefing-selected-categories") ?? [])
            .compactMap { BriefingFeedCategory(rawValue: $0) }
    }

    private var selectedKeywords: [String] {
        UserDefaults.standard.stringArray(forKey: "briefing-selected-keywords") ?? []
    }

    private var isEnabled: Bool { !selectedCategories.isEmpty || !selectedKeywords.isEmpty }

    var body: some View {
        if isEnabled {
            MemdoSection(title: "오늘의 브리핑", trailing: isLoading && items.isEmpty ? "업데이트 중" : nil) {
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
                    if let summary = aiSummary {
                        BriefingSummaryCard(text: summary)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                            BriefingNewsRow(item: item) {
                                selectedURL = item.url
                                showSafari = true
                            }
                            if index < min(4, items.count - 1) {
                                Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                            }
                        }
                    }
                    .memdoRowGroup()
                }
            }
            .task { await loadBriefing() }
            .sheet(isPresented: $showSafari) {
                if let url = selectedURL {
                    BriefingSafariView(url: url).ignoresSafeArea()
                }
            }
        }
    }

    private func loadBriefing() async {
        guard isEnabled else { return }
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

struct BriefingItem: Identifiable {
    enum Channel: Equatable {
        case interestNews
        case scheduleImpact

        var label: String {
            switch self {
            case .interestNews: "키워드 뉴스"
            case .scheduleImpact: "일정 영향"
            }
        }
    }

    let id: String
    let icon: String
    let channel: Channel
    let category: String
    let sourceName: String
    let publishedAt: String
    let title: String
    let summary: String
    let selectionReason: String

    var metadata: String { "\(sourceName) · \(publishedAt)" }

    var tint: Color {
        switch category {
        case "집중": MemdoTheme.mine
        case "날씨": MemdoTheme.google
        default: MemdoTheme.accent
        }
    }

    var tintBackground: Color {
        switch category {
        case "집중": MemdoTheme.mineSoft
        case "날씨": MemdoTheme.googleSoft
        default: MemdoTheme.accentSoft
        }
    }

}

private struct BriefingRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let index: Int
    let item: BriefingItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MemdoMetrics.rowSpacing) {
            Text(String(format: "%02d", index))
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(MemdoTheme.brand)
                .frame(width: MemdoMetrics.rowLeadingWidth, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MemdoTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text("\(item.metadata) · \(item.selectionReason)")
                    .font(.caption2)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, MemdoMetrics.rowInset)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

struct BriefingDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: BriefingItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(item.channel.label, systemImage: item.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.tint)
                    Text(item.title)
                        .font(.title2.bold())
                    Text(item.metadata)
                        .font(.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                    Text(item.summary)
                        .font(.body)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("선정 이유", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MemdoTheme.brand)
                        Text(item.selectionReason)
                            .font(.subheadline.weight(.medium))
                        if item.channel == .scheduleImpact {
                            Text("일정 변경은 Agent가 변경안을 보여준 뒤 적용해요.")
                                .font(.caption)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                    }
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(MemdoTheme.brand)
                            .frame(width: 3)
                    }
                }
                .padding(MemdoMetrics.pagePadding)
            }
            .background(MemdoTheme.background)
            .navigationTitle("브리핑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.medium])
    }
}

// MARK: - Briefing AI Summary Card

private struct BriefingSummaryCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI 요약", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(MemdoTheme.brand)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MemdoTheme.ink)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            MemdoTheme.brandSoft,
            in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                .stroke(MemdoTheme.brand.opacity(0.2), lineWidth: 0.5)
        }
        .padding(.horizontal, MemdoMetrics.rowInset)
        .padding(.bottom, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
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
            HStack(alignment: .top, spacing: MemdoMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    // Category chip + source + relative time
                    HStack(spacing: 6) {
                        Text(item.category.rawValue)
                            .font(.caption2.bold())
                            .foregroundStyle(MemdoTheme.brand)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(MemdoTheme.brandSoft, in: Capsule())

                        Text(item.sourceName)
                            .font(.caption2)
                            .foregroundStyle(MemdoTheme.secondaryInk)

                        if !item.relativeTime.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                            Text(item.relativeTime)
                                .font(.caption2)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                    }
                    .lineLimit(1)

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MemdoTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right.square")
                    .font(.caption.bold())
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .padding(.top, 3)
            }
            .padding(.horizontal, MemdoMetrics.rowInset)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.category.rawValue), \(item.sourceName), \(item.title)")
        .accessibilityHint("탭하면 원문을 열어요")
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
