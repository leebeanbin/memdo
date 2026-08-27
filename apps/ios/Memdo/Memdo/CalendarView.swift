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
    @State private var presentedSheet: CalendarSheetDestination?
    @State private var selectedWorkout: WorkoutLog?
    @State private var searchQuery = ""
    @State private var searchScope = ScheduleSearchScope.all
    @State private var calendarFilter = CalendarDisplayFilter.all
    @State private var monthDirection: Int = 0
    @State private var googleCalendarConnected = false

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
        // Pre-filtered to what could possibly intersect this month before
        // groupedByOccurrenceDay's day-by-day scan.
        let schedules = filteredSchedules.filter {
            !$0.isDone && $0.scheduledDate < monthInterval.end &&
                ($0.endAt ?? $0.scheduledDate) >= monthInterval.start
        }
        let byDay = ScheduleStore.groupedByOccurrenceDay(schedules, in: monthInterval, calendar: calendar)
        return byDay.reduce(into: [:]) { counts, entry in
            counts[calendar.component(.day, from: entry.key)] = entry.value.count
        }
    }

    var body: some View {
        MemdoPage(
            title: "캘린더",
            subtitle: isSearchPresented
                ? "일정, 메모, 장소를 찾아보세요"
                : "일정 \(filteredSchedules.count)개",
            eyebrow: isSearchPresented ? "일정 검색" : displayedMonth.memdoYearMonth,
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
                Group {
                    CalendarMonthCard(
                        filter: $calendarFilter,
                        month: displayedMonth,
                        selectedDate: selectedDate,
                        scheduleCounts: scheduleCounts,
                        workoutDays: workoutDays,
                        googleCalendarConnected: googleCalendarConnected,
                        onSelect: select,
                        onOpen: openDay,
                        onGoToday: goToday,
                        onMoveMonth: moveMonth
                    )
                    .id(displayedMonth)
                    .transition(monthSlideTransition)
                }
                .id(CoachMarkTarget.calendarOverview)
                .coachMarkTarget(.calendarOverview)
                CalendarAgendaSection(
                    date: selectedDate,
                    schedules: selectedAgenda,
                    onAdd: { presentedSheet = .add(selectedDate, filterDefaultKind) },
                    onOpenDay: { presentedSheet = .day(selectedDate) },
                    onOpenSchedule: { presentedSheet = .detail($0) }
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedDate)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .day(let date):
                DayAgendaSheet(date: date)
            case .add(let date, let kind):
                AddScheduleSheet(date: date, defaultKind: kind, onSave: scheduleStore.save)
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
            targetDate = nil
            Task { await scheduleStore.ensureLoaded(for: date) }
        }
        .onChange(of: googleCalendarConnected) { _, connected in
            if !connected && (calendarFilter == .mine || calendarFilter == .google) {
                calendarFilter = .all
            }
        }
        .task { googleCalendarConnected = (try? await scheduleStore.googleCalendarStatus())?.connected == true }
    }

    private func select(_ date: Date) {
        selectedDate = date
        Task { await scheduleStore.ensureLoaded(for: date) }
    }

    private func openDay(_ date: Date) {
        select(date)
        presentedSheet = .day(date)
    }

    private func moveMonth(_ offset: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        let cal = Calendar.current
        monthDirection = offset
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            displayedMonth = month
            if let interval = cal.dateInterval(of: .month, for: month), interval.contains(.now) {
                selectedDate = .now
            } else {
                selectedDate = cal.date(bySetting: .day, value: 1, of: month) ?? month
            }
        }
        Task { await scheduleStore.ensureLoaded(for: month) }
    }

    private var monthSlideTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: monthDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: monthDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var filterDefaultKind: ScheduleKind? {
        switch calendarFilter {
        case .tasks: return .task
        case .events: return .event
        default: return nil
        }
    }

    private func goToday() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            selectedDate = .now
            displayedMonth = Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
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
            .memdoFloatingSurface(interactive: false)

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let weekdays = ["월", "화", "수", "목", "금", "토", "일"]

    @Binding var filter: CalendarDisplayFilter
    @State private var dragOffset: CGFloat = 0
    let month: Date
    let selectedDate: Date
    let scheduleCounts: [Int: Int]
    let workoutDays: Set<Int>
    let googleCalendarConnected: Bool
    let onSelect: (Date) -> Void
    let onOpen: (Date) -> Void
    let onGoToday: () -> Void
    let onMoveMonth: (Int) -> Void

    private var availableFilters: [CalendarDisplayFilter] {
        CalendarDisplayFilter.allCases.filter { f in
            switch f {
            case .mine, .google: googleCalendarConnected
            default: true
            }
        }
    }

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
            .onChanged { value in
                guard !reduceMotion,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = min(max(value.translation.width * 0.2, -24), 24)
            }
            .onEnded { value in
                withAnimation(.spring(duration: 0.3, bounce: 0.25)) { dragOffset = 0 }
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
                        .font(MemdoTypography.captionEmphasis)
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
            .offset(x: dragOffset)

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
                .font(MemdoTypography.sectionTitle)
                .frame(minWidth: 48)

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
            .font(MemdoTypography.captionEmphasis)
            .padding(.horizontal, 10)
            .frame(minHeight: MemdoMetrics.touchTarget)
            .background(MemdoTheme.ink.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(MemdoTheme.outline, lineWidth: 0.5))
            .buttonStyle(.plain)
    }

    private var filterMenu: some View {
        Menu {
            Picker("표시 일정", selection: $filter) {
                ForEach(availableFilters) { filter in
                    Text(filter.title).tag(filter)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(filter.title)
                    .lineLimit(1)
            }
            .font(MemdoTypography.captionEmphasis)
            .foregroundStyle(filter == .all ? MemdoTheme.secondaryInk : MemdoTheme.brand)
            .padding(.horizontal, 10)
            .frame(minHeight: MemdoMetrics.touchTarget)
            .background(filter == .all ? Color.clear : MemdoTheme.brandSoft, in: Capsule())
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
                .font(MemdoTypography.action.monospacedDigit().weight(isSelected ? .bold : .regular))
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
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in onOpen(date) }
        )
        .accessibilityHint("길게 누르면 하루 일정 메뉴가 열립니다")
        .accessibilityLabel(
            date.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR")))
        )
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
    private static let previewLimit = 5
    let date: Date
    let schedules: [ScheduleDetail]
    let onAdd: () -> Void
    let onOpenDay: () -> Void
    let onOpenSchedule: (ScheduleDetail) -> Void

    private var visibleSchedules: [ScheduleDetail] {
        Array(schedules.prefix(Self.previewLimit))
    }
    private var hiddenCount: Int { max(0, schedules.count - Self.previewLimit) }

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

                    if hiddenCount > 0 {
                        Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                        Button(action: onOpenDay) {
                            Label("\(hiddenCount)개 더 보기", systemImage: "calendar")
                                .font(MemdoTypography.action)
                                .foregroundStyle(MemdoTheme.accent)
                                .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .memdoRowGroup()
            }
        }
    }
}

private enum CalendarSheetDestination: Identifiable {
    case day(Date)
    case add(Date, ScheduleKind?)
    case detail(ScheduleDetail)

    var id: String {
        switch self {
        case .day(let date): "day-\(date.timeIntervalSinceReferenceDate)"
        case .add(let date, _): "add-\(date.timeIntervalSinceReferenceDate)"
        case .detail(let schedule): "detail-\(schedule.id)"
        }
    }
}

private enum DayViewMode: String, CaseIterable {
    case timeline = "타임라인"
    case list     = "목록"
}

private struct DayAgendaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(WorkoutStore.self) private var workoutStore
    let date: Date
    @State private var presentedSheet: DayAgendaDestination?
    @State private var selectedWorkout: WorkoutLog?
    @State private var viewMode: DayViewMode = .timeline

    private var daySchedules: [ScheduleDetail] {
        scheduleStore.items(for: date)
    }

    private var dayWorkouts: [WorkoutLog] {
        workoutStore.workouts(on: date)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewMode {
                case .timeline:
                    DayTimelineView(
                        date: date,
                        schedules: daySchedules,
                        workouts: dayWorkouts,
                        onOpenSchedule: { presentedSheet = .detail($0) },
                        onOpenWorkout: { selectedWorkout = $0 }
                    )
                case .list:
                    listContent
                }
            }
            .navigationTitle(date.memdoMonthDay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { presentedSheet = .add } label: { Image(systemName: "plus") }
                        .accessibilityLabel("새 일정 추가")
                }
                ToolbarItem(placement: .principal) {
                    Picker("보기", selection: $viewMode) {
                        ForEach(DayViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
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

    private var listContent: some View {
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
                            .alignmentGuide(.listRowSeparatorLeading) { _ in
                                MemdoMetrics.rowContentLeading
                            }
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
    }
}

// MARK: - Day Timeline (Yotei / CalendarKit inspired)

private struct DayTimelineView: View {
    let date: Date
    let schedules: [ScheduleDetail]
    let workouts: [WorkoutLog]
    let onOpenSchedule: (ScheduleDetail) -> Void
    let onOpenWorkout: (WorkoutLog) -> Void

    private let endHour:   Int = 24
    private let hourHeight: CGFloat = 64
    private let labelWidth: CGFloat = 38

    // Grid opens at 06:00 but extends earlier when a schedule starts before that,
    // so early-morning events aren't rendered off-canvas.
    private var startHour: Int {
        let earliest = timedEvents.compactMap(\.startAt)
            .map { Calendar.current.component(.hour, from: $0) }
            .min()
        return min(6, earliest ?? 6)
    }

    private var timedEvents: [ScheduleDetail] {
        schedules
            .filter { $0.startAt != nil && $0.endAt != nil && $0.kind == .event }
            .sorted { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }
    }

    private var untimedItems: [ScheduleDetail] {
        schedules.filter { $0.startAt == nil || $0.kind == .task }
    }

    private var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if !untimedItems.isEmpty || !workouts.isEmpty {
                        untimedSection
                        Divider()
                    }
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        GeometryReader { geo in
                            let trackWidth = geo.size.width - labelWidth - 12
                            ForEach(timedEvents) { event in
                                TimelineEventBlock(
                                    event: event,
                                    startHour: startHour,
                                    hourHeight: hourHeight,
                                    trackWidth: trackWidth,
                                    labelWidth: labelWidth
                                )
                                .onTapGesture { onOpenSchedule(event) }
                            }
                            if Calendar.current.isDateInToday(date) {
                                TimelineNowLine(
                                    startHour: startHour,
                                    hourHeight: hourHeight,
                                    labelWidth: labelWidth
                                )
                                .id("now")
                            }
                        }
                        .frame(height: totalHeight)
                    }
                    .padding(.horizontal, MemdoMetrics.pagePadding)
                    .padding(.bottom, MemdoMetrics.tabBarClearance)
                }
            }
            .scrollIndicators(.hidden)
            .background(MemdoTheme.background)
            .onAppear {
                let hour = Calendar.current.isDateInToday(date)
                    ? max(startHour, Calendar.current.component(.hour, from: .now) - 1)
                    : 8
                proxy.scrollTo("hour-\(hour)", anchor: .top)
            }
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d", hour))
                        .font(MemdoTypography.caption.monospacedDigit())
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .frame(width: labelWidth, alignment: .trailing)
                        .padding(.trailing, 8)
                    Rectangle()
                        .fill(MemdoTheme.outline.opacity(hour % 3 == 0 ? 0.7 : 0.28))
                        .frame(height: 0.5)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("hour-\(hour)")
            }
        }
    }

    private var untimedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(untimedItems.enumerated()), id: \.element.id) { index, item in
                Button { onOpenSchedule(item) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.kind == .task
                            ? (item.isDone ? "checkmark.circle.fill" : "circle")
                            : "calendar")
                            .font(MemdoTypography.footnote)
                            .foregroundStyle(item.isDone ? MemdoTheme.brand : MemdoTheme.secondaryInk)
                            .frame(width: 18)
                        Text(item.title)
                            .font(MemdoTypography.subtitle)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? MemdoTheme.secondaryInk : MemdoTheme.ink)
                        Spacer()
                    }
                    .padding(.horizontal, MemdoMetrics.pagePadding)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < untimedItems.count - 1 {
                    Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                }
            }
            ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                if !untimedItems.isEmpty || index > 0 {
                    Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                }
                WorkoutLogRow(workout: workout, onTap: { onOpenWorkout(workout) })
                    .padding(.horizontal, 0)
            }
        }
        .background(MemdoTheme.surface)
    }
}

private struct TimelineEventBlock: View {
    let event: ScheduleDetail
    let startHour: Int
    let hourHeight: CGFloat
    let trackWidth: CGFloat
    let labelWidth: CGFloat

    private var topOffset: CGFloat {
        guard let start = event.startAt else { return 0 }
        let cal = Calendar.current
        let h = CGFloat(cal.component(.hour, from: start))
        let m = CGFloat(cal.component(.minute, from: start))
        return max(0, (h * 60 + m - CGFloat(startHour * 60)) / 60 * hourHeight)
    }

    private var blockHeight: CGFloat {
        guard let start = event.startAt, let end = event.endAt else { return hourHeight }
        let secs = max(1800, end.timeIntervalSince(start))
        return CGFloat(secs) / 3600 * hourHeight
    }

    private var timeLabel: String {
        guard let start = event.startAt else { return "" }
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: start)
    }

    // Match ScheduleRow: blocks carry the schedule's category color so the same
    // event looks consistent between the list and the timeline.
    private var blockColor: Color {
        event.color?.swiftUIColor ?? MemdoTheme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.onAccent)
                .lineLimit(blockHeight > 48 ? 2 : 1)
            if blockHeight > 36 {
                Text(timeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(MemdoTheme.onAccent.opacity(0.75))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(width: trackWidth, height: blockHeight, alignment: .topLeading)
        .background(blockColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .offset(x: labelWidth + 8, y: topOffset)
    }
}

private struct TimelineNowLine: View {
    let startHour: Int
    let hourHeight: CGFloat
    let labelWidth: CGFloat

    private var yOffset: CGFloat {
        let cal = Calendar.current
        let h = CGFloat(cal.component(.hour, from: .now))
        let m = CGFloat(cal.component(.minute, from: .now))
        return max(0, (h * 60 + m - CGFloat(startHour * 60)) / 60 * hourHeight - 4)
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: labelWidth + 2)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .padding(.trailing, 2)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1.5)
                .frame(maxWidth: .infinity)
        }
        .offset(y: yOffset)
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

extension Date {
    /// "2026년 8월"
    var memdoYearMonth: String {
        let value = Calendar.current.dateComponents([.year, .month], from: self)
        return "\(value.year ?? 0)년 \(value.month ?? 0)월"
    }

    /// "8월"
    var memdoMonth: String {
        "\(Calendar.current.component(.month, from: self))월"
    }

    /// "8월 12일"
    var memdoMonthDay: String {
        let value = Calendar.current.dateComponents([.month, .day], from: self)
        return "\(value.month ?? 0)월 \(value.day ?? 0)일"
    }

    /// "8월 12일 수요일"
    var memdoMonthDayWeekday: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일 EEEE"
        return fmt.string(from: self)
    }

    /// "2026년 8월 12일 수요일"
    var memdoFullDate: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년 M월 d일 EEEE"
        return fmt.string(from: self)
    }
}
