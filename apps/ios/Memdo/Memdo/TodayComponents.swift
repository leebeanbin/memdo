import SwiftUI

struct TodayHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let eyebrow: String
    let title: String
    let subtitle: String
    let completedCount: Int
    let totalCount: Int
    let onOpenSummary: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    titleGroup
                    HStack {
                        Spacer()
                        progressButton
                    }
                }
            } else {
                HStack(alignment: .top) {
                    titleGroup
                    Spacer()
                    progressButton
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
                            .font(.system(size: 9, weight: .semibold))
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
    let selectedDate: Int
    let scheduleCounts: [Int: Int]
    let onSelect: (Int) -> Void
    let onAdd: (Int) -> Void

    private let dates = Array(zip(["월", "화", "수", "목", "금", "토", "일"], 27...33))

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(dates, id: \.0) { day, date in
                            dateButton(day: day, date: date)
                                .frame(width: 64)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                HStack(spacing: 4) {
                    ForEach(dates, id: \.0) { day, date in
                        dateButton(day: day, date: date)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func dateButton(day: String, date: Int) -> some View {
        let count = scheduleCounts[date, default: 0]

        return Button { onSelect(date) } label: {
                    VStack(spacing: 4) {
                        Text(day)
                            .font(.caption2.weight(.semibold))
                        Text("\(date > 31 ? date - 31 : date)")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 4) {
                            ForEach(0..<min(count, 3), id: \.self) { _ in
                                Circle()
                                    .fill(date == selectedDate ? MemdoTheme.onAccent : MemdoTheme.brand)
                                    .frame(width: 3, height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                    .foregroundStyle(date == selectedDate ? MemdoTheme.onAccent : MemdoTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(date == selectedDate ? MemdoTheme.accent : Color.clear)
                    .clipShape(Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(day)요일 \(date > 31 ? date - 31 : date)일")
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onAdd(date) }
        )
        .accessibilityAddTraits(date == selectedDate ? .isSelected : [])
        .accessibilityValue("\(count)개\(date == selectedDate ? ", 선택됨" : "")")
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
                        .foregroundStyle(MemdoTheme.peach)
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
                        .foregroundStyle(MemdoTheme.peach)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.7), in: Circle())
                }
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [MemdoTheme.peachSoft, MemdoTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: MemdoMetrics.cardRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
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
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

struct TodayBriefingSection: View {
    let onOpen: (BriefingItem) -> Void

    var body: some View {
        MemdoSection(title: "오늘의 브리핑", trailing: "뉴스 2 · 일정 영향 1") {
            VStack(spacing: 0) {
                ForEach(Array(BriefingItem.samples.enumerated()), id: \.element.id) { index, item in
                    Button { onOpen(item) } label: {
                        BriefingRow(index: index + 1, item: item)
                    }
                    .buttonStyle(.plain)

                    if index < BriefingItem.samples.count - 1 {
                        Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                    }
                }
            }
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
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

    static let samples = [
        BriefingItem(
            id: "on-device-ai",
            icon: "cpu",
            channel: .interestNews,
            category: "기술",
            sourceName: "기술 피드",
            publishedAt: "08:20",
            title: "온디바이스 AI가 일상 도구로",
            summary: "개인정보를 기기 안에서 처리하는 흐름이 커지고 있어요.",
            selectionReason: "키워드: AI"
        ),
        BriefingItem(
            id: "calendar-design",
            icon: "rectangle.3.group",
            channel: .interestNews,
            category: "디자인",
            sourceName: "디자인 피드",
            publishedAt: "07:40",
            title: "일정 도구는 더 조용해지고 있어요",
            summary: "기능을 숨기고 필요한 순간에만 드러내는 캘린더 흐름이 늘고 있어요.",
            selectionReason: "키워드: 제품 디자인"
        ),
        BriefingItem(
            id: "evening-weather",
            icon: "cloud.rain",
            channel: .scheduleImpact,
            category: "날씨",
            sourceName: "날씨",
            publishedAt: "방금",
            title: "19시 산책은 30분 뒤로",
            summary: "퇴근 무렵 짧은 소나기가 예상돼요.",
            selectionReason: "일정 영향: 19:00 산책"
        )
    ]
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
