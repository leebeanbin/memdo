import SwiftUI

struct CalendarView: View {
    let coachMarkTarget: CoachMarkTarget?
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isSearchPresented: Bool
    @Binding var targetDate: Date?
    @State private var selectedDate = Date.now
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var showAll = false
    @State private var presentedSheet: CalendarSheetDestination?
    @State private var selectedWorkout: WorkoutLog?
    @State private var searchQuery = ""
    @State private var searchScope = ScheduleSearchScope.all
    @State private var calendarFilter = CalendarDisplayFilter.all

    init(
        coachMarkTarget: CoachMarkTarget? = nil,
        isSearchPresented: Binding<Bool>,
        targetDate: Binding<Date?>
    ) {
        self.coachMarkTarget = coachMarkTarget
        _isSearchPresented = isSearchPresented
        _targetDate = targetDate
    }

    private var filteredSchedules: [ScheduleDetail] {
        scheduleStore.schedules.filter { $0.isActive && calendarFilter.includes($0) }
    }

    private var selectedAgenda: [ScheduleDetail] {
        filteredSchedules
            .filter { $0.occurs(on: selectedDate) }
            .sorted { $0.timeSortKey(on: selectedDate) < $1.timeSortKey(on: selectedDate) }
    }

    private var workoutDays: Set<Int> {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        return Set(workoutStore.workouts
            .filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
            .map { cal.component(.day, from: $0.startedAt) })
    }

    private var scheduleCounts: [Int: Int] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth)
        else { return [:] }
        // Hoisted out of the loop: these were being re-evaluated (a fresh array
        // filter, and Calendar.current's lookup) once per day of the month on
        // every body re-render. Also pre-filtered to what could possibly
        // intersect this month before the day-by-day scan.
        let schedules = filteredSchedules.filter {
            !$0.isDone && $0.scheduledDate < monthInterval.end &&
                ($0.endAt ?? $0.scheduledDate) >= monthInterval.start
        }
        var counts: [Int: Int] = [:]
        var day = monthInterval.start
        while day < monthInterval.end {
            let count = schedules.count { $0.occurs(on: day) }
            if count > 0 { counts[calendar.component(.day, from: day)] = count }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? monthInterval.end
        }
        return counts
    }

    var body: some View {
        MemdoPage(
            title: "캘린더",
            subtitle: isSearchPresented ? "일정, 메모, 장소를 찾아보세요" : displayedMonth.memdoYearMonth,
            eyebrow: "나의 시간",
            headerActionIcon: isSearchPresented ? "xmark" : "magnifyingglass",
            headerActionLabel: isSearchPresented ? "검색 닫기" : "일정 검색",
            headerAction: toggleSearch,
            scrollTarget: coachMarkTarget == .calendarOverview ? .calendarOverview : nil
        ) {
            if isSearchPresented {
                CalendarSearchControls(query: $searchQuery, scope: $searchScope)
                if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MemdoStatusRow(
                        title: "일정을 검색해 보세요",
                        systemImage: "magnifyingglass",
                        detail: "제목뿐 아니라 메모와 장소도 함께 찾아요."
                    )
                } else {
                    ScheduleSearchView(query: $searchQuery, scope: searchScope)
                }
            } else {
                CalendarMonthCard(
                    filter: $calendarFilter,
                    month: displayedMonth,
                    selectedDate: selectedDate,
                    scheduleCounts: scheduleCounts,
                    workoutDays: workoutDays,
                    onSelect: select,
                    onOpen: openDay,
                    onGoToday: goToday,
                    onMoveMonth: moveMonth
                )
                .id(CoachMarkTarget.calendarOverview)
                .coachMarkTarget(.calendarOverview)
                CalendarAgendaSection(
                    date: selectedDate,
                    schedules: selectedAgenda,
                    isExpanded: showAll,
                    onAdd: { presentedSheet = .add(selectedDate) },
                    onToggleExpanded: toggleAgenda,
                    onOpenSchedule: { presentedSheet = .detail($0) }
                )
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .day(let date):
                DayAgendaSheet(date: date)
            case .add(let date):
                AddScheduleSheet(date: date, onSave: scheduleStore.save)
            case .detail(let schedule):
                ScheduleDetailSheet(schedule: schedule, onSave: scheduleStore.save)
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
                .environment(workoutStore)
        }
        .onChange(of: targetDate) { _, date in
            guard let date else { return }
            selectedDate = date
            displayedMonth = Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
            showAll = false
            targetDate = nil
            Task { await scheduleStore.ensureLoaded(for: date) }
        }
    }

    private func select(_ date: Date) {
        selectedDate = date
        showAll = false
        Task { await scheduleStore.ensureLoaded(for: date) }
    }

    private func openDay(_ date: Date) {
        select(date)
        presentedSheet = .day(date)
    }

    private func moveMonth(_ offset: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            displayedMonth = month
            selectedDate = Calendar.current.date(bySetting: .day, value: 1, of: month) ?? month
            showAll = false
        }
        Task { await scheduleStore.ensureLoaded(for: month) }
    }

    private func goToday() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            selectedDate = .now
            displayedMonth = Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
            showAll = false
        }
    }

    private func toggleAgenda() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            showAll.toggle()
        }
    }

    private func toggleSearch() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            isSearchPresented.toggle()
            if !isSearchPresented { searchQuery = "" }
        }
    }
}

private struct CalendarSearchControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var query: String
    @Binding var scope: ScheduleSearchScope
    @FocusState private var isFocused: Bool

    var body: some View {
        controls
            .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
            .onAppear { isFocused = true }
    }

    private var controls: some View {
        VStack(spacing: MemdoMetrics.sectionContentSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .accessibilityHidden(true)
                TextField("일정, 메모, 장소", text: $query)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MemdoTheme.secondaryInk)
                            .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색어 지우기")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: MemdoMetrics.touchTarget)
            .memdoFloatingSurface()

            Picker("검색 범위", selection: $scope) {
                ForEach(ScheduleSearchScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityValue(scope.title)
        }
    }
}

private struct CalendarMonthCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let weekdays = ["월", "화", "수", "목", "금", "토", "일"]

    @Binding var filter: CalendarDisplayFilter
    let month: Date
    let selectedDate: Date
    let scheduleCounts: [Int: Int]
    let workoutDays: Set<Int>
    let onSelect: (Date) -> Void
    let onOpen: (Date) -> Void
    let onGoToday: () -> Void
    let onMoveMonth: (Int) -> Void

    private var calendarDays: [Date?] {
        let calendar = Calendar.current
        guard let dayRange = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return [] }
        let mondayOffset = (calendar.component(.weekday, from: firstDay) + 5) % 7
        return Array(repeating: nil, count: mondayOffset) + dayRange.compactMap {
            calendar.date(bySetting: .day, value: $0, of: firstDay)
        }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 44)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
                      abs(value.translation.width) > 64 else { return }
                onMoveMonth(value.translation.width < 0 ? 1 : -1)
            }
    }

    var body: some View {
        VStack(spacing: MemdoMetrics.sectionContentSpacing) {
            monthControls
            .contentShape(Rectangle())
            .highPriorityGesture(monthSwipeGesture)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.bold())
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
                ForEach(calendarDays.indices, id: \.self) { index in
                    if let date = calendarDays[index] {
                        dayButton(date)
                    } else {
                        Color.clear.frame(minHeight: MemdoMetrics.touchTarget)
                    }
                }
            }
            .dynamicTypeSize(.small ... .large)

        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .memdoRowGroup()
        .accessibilityAction(named: "이전 달") { onMoveMonth(-1) }
        .accessibilityAction(named: "다음 달") { onMoveMonth(1) }
    }

    @ViewBuilder
    private var monthControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 4) {
                HStack {
                    monthNavigation
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    todayButton
                    Spacer(minLength: 0)
                    filterMenu
                }
            }
        } else {
            HStack(spacing: 8) {
                monthNavigation
                Spacer(minLength: 4)
                todayButton
                filterMenu
            }
        }
    }

    private var monthNavigation: some View {
        HStack(spacing: 0) {
            Button { onMoveMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("이전 달")

            Text(month.memdoMonth)
                .font(.headline)
                .frame(minWidth: 52)

            Button { onMoveMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("다음 달")
        }
    }

    private var todayButton: some View {
        Button("오늘", action: onGoToday)
            .font(.caption.weight(.semibold))
            .frame(minHeight: MemdoMetrics.touchTarget)
            .buttonStyle(.plain)
    }

    private var filterMenu: some View {
        Menu {
            Picker("표시 일정", selection: $filter) {
                ForEach(CalendarDisplayFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(filter.title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(filter == .all ? MemdoTheme.ink : MemdoTheme.brand)
            .frame(minHeight: MemdoMetrics.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("일정 필터")
        .accessibilityValue(filter.title)
    }

    private func dayButton(_ date: Date) -> some View {
        let day = Calendar.current.component(.day, from: date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let count = scheduleCounts[day, default: 0]
        let hasWorkout = workoutDays.contains(day)

        return Button { onSelect(date) } label: {
            Text("\(day)")
                .font(.subheadline.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? MemdoTheme.onAccent : MemdoTheme.ink)
                .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
                .background(isSelected ? MemdoTheme.accent : .clear, in: Circle())
                .overlay(alignment: .bottom) {
                    HStack(spacing: 3) {
                        MemdoScheduleCountDots(count: count, isEmphasized: isSelected)
                        if hasWorkout {
                            Circle()
                                .fill(isSelected ? MemdoTheme.onAccent.opacity(0.8) : Color.orange)
                                .frame(width: 3, height: 3)
                        }
                    }
                    .frame(height: 4)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onOpen(date) }
        )
        .accessibilityHint("길게 누르면 하루 일정 메뉴가 열립니다")
        .accessibilityLabel(date.formatted(.dateTime.month().day().weekday(.wide)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue("일정 \(count)개\(hasWorkout ? ", 운동 있음" : "")\(isSelected ? ", 선택됨" : "")")
        .accessibilityAction(named: "하루 일정 메뉴 열기") { onOpen(date) }
    }
}

private enum CalendarDisplayFilter: String, CaseIterable, Identifiable {
    case all
    case events
    case tasks
    case personal
    case work
    case mine
    case google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .events: "시간 일정"
        case .tasks: "할 일"
        case .personal: "개인"
        case .work: "업무"
        case .mine: "내 일정"
        case .google: "Google"
        }
    }

    func includes(_ schedule: ScheduleDetail) -> Bool {
        switch self {
        case .all: true
        case .events: schedule.kind == .event
        case .tasks: schedule.kind == .task
        case .personal: schedule.calendar.purpose == "personal"
        case .work: schedule.calendar.purpose == "work"
        case .mine: !schedule.isExternal
        case .google: schedule.isExternal
        }
    }
}

private struct CalendarAgendaSection: View {
    let date: Date
    let schedules: [ScheduleDetail]
    let isExpanded: Bool
    let onAdd: () -> Void
    let onToggleExpanded: () -> Void
    let onOpenSchedule: (ScheduleDetail) -> Void

    private var visibleSchedules: [ScheduleDetail] {
        Array(schedules.prefix(isExpanded ? schedules.count : 3))
    }

    var body: some View {
        MemdoSection(
            title: date.memdoMonthDay,
            trailing: "\(schedules.count)개",
            actionIcon: "plus",
            actionLabel: "새 일정 추가",
            action: onAdd
        ) {
            if schedules.isEmpty {
                MemdoStatusRow(
                    title: "등록된 일정이 없어요",
                    systemImage: "calendar.badge.plus",
                    detail: "위의 + 또는 날짜 길게 누르기로 시작해 보세요.",
                    tint: MemdoTheme.brand
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleSchedules.enumerated()), id: \.element.id) { index, schedule in
                        ScheduleRow(
                            schedule: schedule,
                            context: .timeline,
                            onOpen: { onOpenSchedule(schedule) }
                        )
                        if index < visibleSchedules.count - 1 {
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
}

private enum CalendarSheetDestination: Identifiable {
    case day(Date)
    case add(Date)
    case detail(ScheduleDetail)

    var id: String {
        switch self {
        case .day(let date): "day-\(date.timeIntervalSinceReferenceDate)"
        case .add(let date): "add-\(date.timeIntervalSinceReferenceDate)"
        case .detail(let schedule): "detail-\(schedule.id)"
        }
    }
}

private struct DayAgendaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(WorkoutStore.self) private var workoutStore
    let date: Date
    @State private var presentedSheet: DayAgendaDestination?
    @State private var selectedWorkout: WorkoutLog?

    private var daySchedules: [ScheduleDetail] {
        scheduleStore.items(for: date)
    }

    private var dayWorkouts: [WorkoutLog] {
        workoutStore.workouts(on: date)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(
                        Calendar.current.isDateInToday(date) ? "오늘" : date < .now ? "지난 일정" : "예정",
                        value: "\(daySchedules.count)개"
                    )
                }
                if daySchedules.isEmpty && dayWorkouts.isEmpty {
                    ContentUnavailableView(
                        "비어 있는 하루예요",
                        systemImage: "calendar.badge.plus",
                        description: Text("편한 시간에 첫 일정을 추가해 보세요.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    if !daySchedules.isEmpty {
                        Section("일정") {
                            ForEach(daySchedules) { schedule in
                                ScheduleRow(
                                    schedule: schedule,
                                    context: .timeline,
                                    onOpen: { presentedSheet = .detail(schedule) }
                                )
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                    }
                    if !dayWorkouts.isEmpty {
                        Section("운동") {
                            ForEach(dayWorkouts) { workout in
                                WorkoutLogRow(workout: workout) { selectedWorkout = workout }
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                    }
                }

            }
            .memdoSystemList()
            .navigationTitle(date.memdoMonthDay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentedSheet = .add
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("새 일정 추가")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(MemdoTheme.accent)
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .add:
                AddScheduleSheet(date: date, onSave: scheduleStore.save)
            case .detail(let schedule):
                ScheduleDetailSheet(schedule: schedule, onSave: scheduleStore.save)
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
                .environment(workoutStore)
        }
        .memdoSheetPresentation()
    }
}

private enum DayAgendaDestination: Identifiable {
    case add
    case detail(ScheduleDetail)

    var id: String {
        switch self {
        case .add: "add"
        case .detail(let schedule): "detail-\(schedule.id)"
        }
    }
}

private extension Date {
    var memdoYearMonth: String {
        let value = Calendar.current.dateComponents([.year, .month], from: self)
        return "\(value.year ?? 0)년 \(value.month ?? 0)월"
    }

    var memdoMonth: String {
        "\(Calendar.current.component(.month, from: self))월"
    }

    var memdoMonthDay: String {
        let value = Calendar.current.dateComponents([.month, .day], from: self)
        return "\(value.month ?? 0)월 \(value.day ?? 0)일"
    }
}
