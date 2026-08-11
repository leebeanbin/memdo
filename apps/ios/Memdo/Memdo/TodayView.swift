import SwiftUI

private struct TodayScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct TodayView: View {
    let coachMarkTarget: CoachMarkTarget?
    let onOpenGuide: () -> Void
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentedSheet: TodaySheetDestination?
    @State private var selectedWorkout: WorkoutLog?
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var showAllSchedules = false
    @State private var autoExpandArmed = true

    init(
        coachMarkTarget: CoachMarkTarget? = nil,
        onOpenGuide: @escaping () -> Void = {}
    ) {
        self.coachMarkTarget = coachMarkTarget
        self.onOpenGuide = onOpenGuide
    }

    private var schedules: [ScheduleDetail] {
        scheduleStore.items(for: selectedDate)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var scheduleCounts: [Date: Int] {
        Dictionary(uniqueKeysWithValues: weekDates.map { date in
            (date, scheduleStore.items(for: date).filter { !$0.isDone }.count)
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
                ScrollViewReader { proxy in
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
                            eyebrow: isToday ? "좋은 하루예요" : selectedDate < .now ? "지난 하루" : "다가오는 하루",
                            title: isToday ? "오늘" : selectedDate.formatted(.dateTime.month().day()),
                            subtitle: dateSubtitle,
                            completedCount: completedCount,
                            totalCount: taskCount,
                            onOpenSummary: openSummary,
                            onOpenGuide: onOpenGuide
                        )
                        .id(CoachMarkTarget.todayOverview)
                        .coachMarkTarget(.todayOverview)
                        TodayWeekIndex(
                            dates: weekDates,
                            selectedDate: selectedDate,
                            scheduleCounts: scheduleCounts,
                            onSelect: selectDate,
                            onAdd: openAddSchedule
                        )
                            .id(CoachMarkTarget.todayDates)
                            .coachMarkTarget(.todayDates)
                            .highPriorityGesture(
                                dateSwipeGesture,
                                including: dynamicTypeSize.isAccessibilitySize ? .subviews : .all
                            )

                        VStack(spacing: 0) {
                            if schedules.isEmpty {
                                TodayIntentionPrompt(isToday: isToday, onAdd: openAddSchedule)
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
                        }
                        .id(CoachMarkTarget.todaySchedule)
                        .coachMarkTarget(.todaySchedule)

                        TodayBriefingSection()
                            .id(CoachMarkTarget.todayBriefing)
                            .coachMarkTarget(.todayBriefing)
                        }
                        .padding(.horizontal, MemdoMetrics.pagePadding)
                        .padding(
                            .bottom,
                            coachMarkTarget?.isTodayContent == true
                                ? MemdoMetrics.tabBarClearance + 280
                                : MemdoMetrics.tabBarClearance
                        )
                    }
                    .coordinateSpace(name: "today-scroll")
                    .scrollIndicators(.hidden)
                    .onChange(of: coachMarkTarget, initial: true) { _, target in
                        guard let target, target.isTodayContent else { return }
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        }
                    }
                    .onPreferenceChange(TodayScrollOffsetKey.self) { offset in
                        if offset > -40 {
                            autoExpandArmed = true
                        }
                        guard autoExpandArmed, offset < -120, schedules.count > 3, !showAllSchedules else { return }
                        autoExpandArmed = false
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            showAllSchedules = true
                        }
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
                }
            }
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailSheet(workout: workout)
                    .environment(workoutStore)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(MemdoTheme.accent)
        .sensoryFeedback(.selection, trigger: selectedDate)
        .accessibilityAction(named: "이전 날짜") { moveDate(by: -1) }
        .accessibilityAction(named: "다음 날짜") { moveDate(by: 1) }
    }

    private var dateSubtitle: String {
        selectedDate.formatted(.dateTime.year().month().day().weekday(.wide))
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        showAllSchedules = false
        autoExpandArmed = true
        Task { await scheduleStore.ensureLoaded(for: selectedDate) }
    }

    private func moveDate(by offset: Int) {
        guard let nextDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            selectDate(nextDate)
        }
    }

    private func openAddSchedule() {
        openAddSchedule(selectedDate)
    }

    private func openAddSchedule(_ date: Date) {
        selectDate(date)
        presentedSheet = .addTask(date)
    }

    private func openSummary() {
        presentedSheet = .dailySummary(selectedDate)
    }

    private func openSchedule(_ schedule: ScheduleDetail) {
        presentedSheet = .detail(schedule)
    }

    private func toggleDone(_ schedule: ScheduleDetail) {
        scheduleStore.toggleDone(id: schedule.id)
    }

    private func toggleSchedules() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            showAllSchedules.toggle()
        }
        if !showAllSchedules {
            autoExpandArmed = false
        }
    }

}

private extension CoachMarkTarget {
    var isTodayContent: Bool {
        switch self {
        case .todayOverview, .todayDates, .todaySchedule, .todayBriefing: true
        default: false
        }
    }
}

enum TodaySheetDestination: Identifiable {
    case addTask(Date)
    case dailySummary(Date)
    case detail(ScheduleDetail)

    var id: String {
        switch self {
        case .addTask(let date): "addTask-\(date.timeIntervalSinceReferenceDate)"
        case .dailySummary(let date): "dailySummary-\(date.timeIntervalSinceReferenceDate)"
        case .detail(let schedule): "detail-\(schedule.id)"
        }
    }
}

#if DEBUG
struct TodayView_Previews: PreviewProvider {
    static var previews: some View {
        TodayView()
            .environment(ScheduleStore.preview())
    }
}
#endif
