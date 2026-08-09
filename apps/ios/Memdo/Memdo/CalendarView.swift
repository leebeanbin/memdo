import SwiftUI

struct CalendarView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Binding var isSearchPresented: Bool
    @Binding var targetDate: Date?
    @State private var selectedDate = Date.now
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var showAll = false
    @State private var presentedSheet: CalendarSheetDestination?
    @State private var searchQuery = ""
    @State private var searchScope = ScheduleSearchScope.all
    @State private var calendarFilter = CalendarDisplayFilter.all

    private var filteredSchedules: [ScheduleDetail] {
        scheduleStore.schedules.filter { $0.isActive && calendarFilter.includes($0) }
    }

    private var selectedAgenda: [ScheduleDetail] {
        filteredSchedules
            .filter { $0.occurs(on: selectedDate) }
            .sorted { $0.timeSortKey < $1.timeSortKey }
    }

    private var scheduleCounts: [Int: Int] {
        guard let monthInterval = Calendar.current.dateInterval(of: .month, for: displayedMonth)
        else { return [:] }
        var counts: [Int: Int] = [:]
        var day = monthInterval.start
        while day < monthInterval.end {
            let count = filteredSchedules.filter { !$0.isDone && $0.occurs(on: day) }.count
            if count > 0 { counts[Calendar.current.component(.day, from: day)] = count }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? monthInterval.end
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
            headerAction: toggleSearch
        ) {
            if isSearchPresented {
                CalendarSearchControls(query: $searchQuery, scope: $searchScope)
                if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "일정을 검색해 보세요",
                        systemImage: "magnifyingglass",
                        description: Text("제목뿐 아니라 메모와 장소도 함께 찾아요.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ScheduleSearchView(query: $searchQuery, scope: searchScope)
                }
            } else {
                CalendarMonthCard(
                    filter: $calendarFilter,
                    month: displayedMonth,
                    selectedDate: selectedDate,
                    scheduleCounts: scheduleCounts,
                    onSelect: select,
                    onOpen: openDay,
                    onGoToday: goToday,
                    onMoveMonth: moveMonth
                )
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
        withAnimation(.snappy(duration: 0.25)) {
            displayedMonth = month
            selectedDate = Calendar.current.date(bySetting: .day, value: 1, of: month) ?? month
            showAll = false
        }
        Task { await scheduleStore.ensureLoaded(for: month) }
    }

    private func goToday() {
        withAnimation(.snappy(duration: 0.25)) {
            selectedDate = .now
            displayedMonth = Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
            showAll = false
        }
    }

    private func toggleAgenda() {
        withAnimation(.easeOut(duration: 0.2)) {
            showAll.toggle()
        }
    }

    private func toggleSearch() {
        withAnimation(.snappy(duration: 0.25)) {
            isSearchPresented.toggle()
            if !isSearchPresented { searchQuery = "" }
        }
    }
}

private struct CalendarSearchControls: View {
    @Binding var query: String
    @Binding var scope: ScheduleSearchScope
    @FocusState private var isFocused: Bool

    var body: some View {
        controls
            .transition(.move(edge: .top).combined(with: .opacity))
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
            .memdoFloatingSurface(radius: 22)

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
    private let weekdays = ["월", "화", "수", "목", "금", "토", "일"]

    @Binding var filter: CalendarDisplayFilter
    let month: Date
    let selectedDate: Date
    let scheduleCounts: [Int: Int]
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
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Button { onMoveMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("이전 달")

                    VStack(spacing: 4) {
                        Text(month.memdoMonth)
                            .font(.headline)
                        if filter != .all {
                            Text(filter.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MemdoTheme.brand)
                        }
                    }
                    .frame(minWidth: 52)

                    Button { onMoveMonth(1) } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("다음 달")
                }
                Spacer(minLength: 4)
                Button("오늘", action: onGoToday)
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: MemdoMetrics.touchTarget)
                    .buttonStyle(.plain)
                Menu {
                    Picker("표시 일정", selection: $filter) {
                        ForEach(CalendarDisplayFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                } label: {
                    MemdoIconButtonLabel(systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.plain)
                .memdoFloatingSurface(radius: 22)
                .accessibilityLabel("일정 필터")
                .accessibilityValue(filter.title)
            }
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

    private func dayButton(_ date: Date) -> some View {
        let day = Calendar.current.component(.day, from: date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let count = scheduleCounts[day, default: 0]

        return Button { onSelect(date) } label: {
            Text("\(day)")
                .font(.subheadline.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? MemdoTheme.onAccent : MemdoTheme.ink)
                .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
                .background(isSelected ? MemdoTheme.accent : .clear, in: Circle())
                .overlay(alignment: .bottom) {
                    MemdoScheduleCountDots(count: count, isEmphasized: isSelected)
                        .padding(.bottom, 4)
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
        .accessibilityValue("일정 \(count)개\(isSelected ? ", 선택됨" : "")")
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
                ContentUnavailableView(
                    "등록된 일정이 없어요",
                    systemImage: "calendar.badge.plus",
                    description: Text("위의 + 또는 날짜 길게 누르기로 시작해 보세요.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
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
    let date: Date
    @State private var presentedSheet: DayAgendaDestination?

    private var daySchedules: [ScheduleDetail] {
        scheduleStore.items(for: date)
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
                if daySchedules.isEmpty {
                    ContentUnavailableView(
                        "비어 있는 하루예요",
                        systemImage: "calendar.badge.plus",
                        description: Text("편한 시간에 첫 일정을 추가해 보세요.")
                    )
                    .listRowBackground(Color.clear)
                } else {
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
