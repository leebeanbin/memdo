import SwiftUI

private struct TodayScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct TodayView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var presentedSheet: TodaySheetDestination?
    @State private var selectedDate = 31
    @State private var showAllSchedules = false

    private var schedules: [ScheduleDetail] {
        scheduleStore.items(for: date(for: selectedDate))
    }

    private var scheduleCounts: [Int: Int] {
        Dictionary(uniqueKeysWithValues: (27...33).map { day in
            (day, scheduleStore.items(for: date(for: day)).filter { !$0.isDone }.count)
        })
    }

    private var completedCount: Int {
        schedules.filter { $0.kind == .task && $0.isDone }.count
    }

    private var taskCount: Int {
        schedules.filter { $0.kind == .task }.count
    }

    private var dateSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 44)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
                      abs(value.translation.width) > 64 else { return }
                moveDate(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MemdoPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TodayScrollOffsetKey.self,
                                value: proxy.frame(in: .named("today-scroll")).minY
                            )
                        }
                        .frame(height: 0)

                        TodayHeader(
                            eyebrow: selectedDate == 31 ? "좋은 오후예요" : selectedDate < 31 ? "지난 하루" : "다가오는 하루",
                            title: selectedDate == 31 ? "오늘" : selectedDate > 31 ? "8월 \(displayDate(selectedDate))일" : "7월 \(selectedDate)일",
                            subtitle: dateSubtitle,
                            completedCount: completedCount,
                            totalCount: taskCount,
                            onOpenSummary: openSummary
                        )
                        TodayWeekIndex(
                            selectedDate: selectedDate,
                            scheduleCounts: scheduleCounts,
                            onSelect: selectDate,
                            onAdd: openAddSchedule
                        )
                            .highPriorityGesture(dateSwipeGesture)

                        if schedules.isEmpty {
                            TodayIntentionPrompt(isToday: selectedDate == 31, onAdd: openAddSchedule)
                        } else {
                            TodayScheduleSection(
                                schedules: schedules,
                                isExpanded: showAllSchedules,
                                onAdd: { openAddSchedule(selectedDate) },
                                onToggleExpanded: toggleSchedules,
                                onOpenSchedule: openSchedule,
                                onToggleDone: toggleDone
                            )
                        }

                        TodayBriefingSection(onOpen: openBriefing)
                    }
                    .padding(.horizontal, MemdoMetrics.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, MemdoMetrics.tabBarClearance)
                }
                .coordinateSpace(name: "today-scroll")
                .scrollIndicators(.hidden)
                .onPreferenceChange(TodayScrollOffsetKey.self) { offset in
                    guard offset < -120, schedules.count > 3, !showAllSchedules else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        showAllSchedules = true
                    }
                }
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .addTask(let date):
                    AddScheduleSheet(date: date, onSave: scheduleStore.save)
                case .dailySummary(let date):
                    DailySummaryView(date: date)
                case .detail(let schedule):
                    ScheduleDetailSheet(schedule: schedule, onSave: scheduleStore.save)
                case .briefing(let item):
                    BriefingDetailSheet(item: item)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(MemdoTheme.accent)
        .sensoryFeedback(.selection, trigger: selectedDate)
        .accessibilityAction(named: "이전 날짜") { moveDate(by: -1) }
        .accessibilityAction(named: "다음 날짜") { moveDate(by: 1) }
    }

    private var dateSubtitle: String {
        let weekdays = [27: "월요일", 28: "화요일", 29: "수요일", 30: "목요일", 31: "금요일", 32: "토요일", 33: "일요일"]
        let month = selectedDate > 31 ? 8 : 7
        return "\(month)월 \(displayDate(selectedDate))일 \(weekdays[selectedDate] ?? "")"
    }

    private func displayDate(_ date: Int) -> Int {
        date > 31 ? date - 31 : date
    }

    private func selectDate(_ date: Int) {
        selectedDate = date
        showAllSchedules = false
    }

    private func moveDate(by offset: Int) {
        let nextDate = min(max(selectedDate + offset, 27), 33)
        guard nextDate != selectedDate else { return }
        withAnimation(.snappy(duration: 0.25)) {
            selectDate(nextDate)
        }
    }

    private func openAddSchedule() {
        openAddSchedule(selectedDate)
    }

    private func openAddSchedule(_ day: Int) {
        selectDate(day)
        presentedSheet = .addTask(date(for: day))
    }

    private func openSummary() {
        presentedSheet = .dailySummary(date(for: selectedDate))
    }

    private func openSchedule(_ schedule: ScheduleDetail) {
        presentedSheet = .detail(schedule)
    }

    private func toggleDone(_ schedule: ScheduleDetail) {
        scheduleStore.toggleDone(id: schedule.id)
    }

    private func toggleSchedules() {
        withAnimation(.easeOut(duration: 0.2)) {
            showAllSchedules.toggle()
        }
    }

    private func openBriefing(_ item: BriefingItem) {
        presentedSheet = .briefing(item)
    }

    private func date(for day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: day)) ?? .now
    }
}

enum TodaySheetDestination: Identifiable {
    case addTask(Date)
    case dailySummary(Date)
    case detail(ScheduleDetail)
    case briefing(BriefingItem)

    var id: String {
        switch self {
        case .addTask(let date): "addTask-\(date.timeIntervalSinceReferenceDate)"
        case .dailySummary(let date): "dailySummary-\(date.timeIntervalSinceReferenceDate)"
        case .detail(let schedule): "detail-\(schedule.id)"
        case .briefing(let item): "briefing-\(item.id)"
        }
    }
}

struct TodayView_Previews: PreviewProvider {
    static var previews: some View {
        TodayView()
            .environment(ScheduleStore())
    }
}
