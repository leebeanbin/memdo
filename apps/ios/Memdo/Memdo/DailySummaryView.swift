import SwiftUI

struct DailySummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var scope = SummaryScope.today
    @State private var pendingDeletion: ScheduleDetail?
    @State private var pendingMove: ScheduleDetail?

    let date: Date

    init(date: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 31)) ?? .now) {
        self.date = date
    }

    private var tasks: [ScheduleDetail] {
        let interval = scope.interval(endingAt: date)
        return scheduleStore.schedules
            .filter {
                $0.kind == .task &&
                $0.startAt >= interval.start &&
                $0.startAt < interval.end
            }
            .sorted { scope == .today ? $0.timeSortKey < $1.timeSortKey : $0.timeSortKey > $1.timeSortKey }
    }

    private var completedTasks: [ScheduleDetail] {
        tasks.filter(\.isDone)
    }

    private var incompleteTasks: [ScheduleDetail] {
        tasks.filter { !$0.isDone }
    }

    var body: some View {
        MemdoPage(
            title: scope.title,
            subtitle: scope.subtitle(endingAt: date),
            eyebrow: scope == .today ? "하루 마무리" : "기록 회고",
            headerActionIcon: "xmark",
            headerActionLabel: "요약 닫기",
            headerAction: { dismiss() }
        ) {
            SummaryScopePicker(selection: $scope)
            SummaryProgressLine(
                completedCount: completedTasks.count,
                totalCount: tasks.count,
                incompleteLabel: scope == .today ? "확인" : "놓침"
            )
            if scope == .today {
                SummaryInsightSection(remainingCount: incompleteTasks.count)
                SummaryReviewSection(
                    reviews: incompleteTasks,
                    onComplete: complete,
                    onMoveToTomorrow: moveToTomorrow,
                    onChooseDate: { pendingMove = $0 },
                    onDelete: { pendingDeletion = $0 }
                )
            } else {
                SummaryHistorySection(status: .completed, schedules: completedTasks)
                SummaryHistorySection(status: .missed, schedules: incompleteTasks)
            }
        }
        .memdoSheetPresentation([.large])
        .sheet(item: $pendingMove) { schedule in
            MoveScheduleSheet(schedule: schedule) { newDate in
                scheduleStore.move(id: schedule.id, to: newDate)
            }
        }
        .confirmationDialog(
            "일정을 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let pendingDeletion { scheduleStore.delete(id: pendingDeletion.id) }
                pendingDeletion = nil
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 작업은 되돌릴 수 없어요.")
        }
    }

    private func complete(_ schedule: ScheduleDetail) {
        var completed = schedule
        completed.isDone = true
        scheduleStore.save(completed)
    }

    private func moveToTomorrow(_ schedule: ScheduleDetail) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        scheduleStore.move(id: schedule.id, to: tomorrow)
    }
}

private enum SummaryScope: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "오늘 요약"
        case .week: "지난 7일"
        case .month: "지난 30일"
        }
    }

    var segmentTitle: String {
        switch self {
        case .today: "오늘"
        case .week: "7일"
        case .month: "30일"
        }
    }

    func interval(endingAt date: Date) -> DateInterval {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        switch self {
        case .today:
            return DateInterval(
                start: startOfDay,
                end: calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            )
        case .week:
            return DateInterval(
                start: calendar.date(byAdding: .day, value: -7, to: startOfDay) ?? startOfDay,
                end: startOfDay
            )
        case .month:
            return DateInterval(
                start: calendar.date(byAdding: .day, value: -30, to: startOfDay) ?? startOfDay,
                end: startOfDay
            )
        }
    }

    func subtitle(endingAt date: Date) -> String {
        let formatter = Date.FormatStyle.dateTime
            .month(.wide)
            .day()
            .locale(Locale(identifier: "ko_KR"))
        if self == .today {
            return date.formatted(
                .dateTime
                    .month(.wide)
                    .day()
                    .weekday(.wide)
                    .locale(Locale(identifier: "ko_KR"))
            )
        }
        let range = interval(endingAt: date)
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        return "\(range.start.formatted(formatter))–\(lastDay.formatted(formatter))"
    }
}

private struct SummaryScopePicker: View {
    @Binding var selection: SummaryScope

    var body: some View {
        Picker("요약 기간", selection: $selection) {
            ForEach(SummaryScope.allCases) { scope in
                Text(scope.segmentTitle).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityValue(selection.title)
    }
}

private struct SummaryProgressLine: View {
    let completedCount: Int
    let totalCount: Int
    let incompleteLabel: String

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("완료 \(completedCount)")
                    .font(.subheadline.weight(.semibold))
                Text("\(incompleteLabel) \(max(totalCount - completedCount, 0))")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                Spacer(minLength: 0)
                Text("\(completedCount)/\(totalCount)")
                    .font(.caption.monospacedDigit().weight(.bold))
            }
            ProgressView(value: totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount))
                .tint(MemdoTheme.accent)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private enum SummaryHistoryStatus {
    case completed
    case missed

    var title: String {
        switch self {
        case .completed: "잘 끝낸 작업"
        case .missed: "놓치고 지난 작업"
        }
    }

    var systemImage: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .missed: "clock.badge.exclamationmark"
        }
    }
}

private struct SummaryHistorySection: View {
    @State private var isExpanded = false
    let status: SummaryHistoryStatus
    let schedules: [ScheduleDetail]

    private var visibleSchedules: [ScheduleDetail] {
        Array(schedules.prefix(isExpanded ? schedules.count : 3))
    }

    var body: some View {
        MemdoSection(title: status.title, trailing: "\(schedules.count)개") {
            if schedules.isEmpty {
                ContentUnavailableView(
                    status == .completed ? "완료 기록이 없어요" : "놓친 작업이 없어요",
                    systemImage: status.systemImage
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleSchedules) { schedule in
                        SummaryHistoryRow(schedule: schedule, status: status)
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
                            action: { withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() } }
                        )
                    }
                }
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }
}

private struct SummaryHistoryRow: View {
    let schedule: ScheduleDetail
    let status: SummaryHistoryStatus

    var body: some View {
        HStack(spacing: MemdoMetrics.rowSpacing) {
            Image(systemName: status.systemImage)
                .font(.title3)
                .foregroundStyle(status == .completed ? MemdoTheme.secondaryInk : MemdoTheme.brand)
                .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(schedule.dateText) · \(schedule.displayTime)")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MemdoMetrics.rowInset)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct SummaryReviewSection: View {
    let reviews: [ScheduleDetail]
    let onComplete: (ScheduleDetail) -> Void
    let onMoveToTomorrow: (ScheduleDetail) -> Void
    let onChooseDate: (ScheduleDetail) -> Void
    let onDelete: (ScheduleDetail) -> Void

    var body: some View {
        MemdoSection(title: "결정이 필요한 일정", trailing: "\(reviews.count)개") {
            if reviews.isEmpty {
                ContentUnavailableView("정리가 끝났어요", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 0) {
                    ForEach(reviews) { schedule in
                        SummaryReviewRow(
                            schedule: schedule,
                            onComplete: { onComplete(schedule) },
                            onMoveToTomorrow: { onMoveToTomorrow(schedule) },
                            onChooseDate: { onChooseDate(schedule) },
                            onDelete: { onDelete(schedule) }
                        )
                        if schedule.id != reviews.last?.id {
                            Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                        }
                    }
                }
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }
}

private struct SummaryInsightSection: View {
    let remainingCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MemdoMetrics.rowSpacing) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoTheme.brand)
                .frame(width: MemdoMetrics.rowLeadingWidth)
                .accessibilityHidden(true)
            Text(remainingCount == 0
                 ? "Agent · 오늘의 할 일을 모두 정리했어요."
                 : "Agent · 남은 \(remainingCount)개는 완료하거나 다음 날짜로 옮겨보세요.")
                .font(.subheadline)
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
        .padding(.horizontal, MemdoMetrics.rowInset)
        .accessibilityElement(children: .combine)
    }
}

private struct SummaryReviewRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let schedule: ScheduleDetail
    let onComplete: () -> Void
    let onMoveToTomorrow: () -> Void
    let onChooseDate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: MemdoMetrics.rowSpacing) {
                        completeButton
                        titleBlock
                    }
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        tomorrowButton
                        moreMenu
                    }
                }
            } else {
                HStack(spacing: MemdoMetrics.rowSpacing) {
                    completeButton
                    titleBlock
                    Spacer(minLength: 4)
                    tomorrowButton
                    moreMenu
                }
            }
        }
        .padding(.horizontal, MemdoMetrics.rowInset)
        .padding(.vertical, 4)
    }

    private var completeButton: some View {
        Button(action: onComplete) {
            Image(systemName: "circle")
                .font(.title3)
                .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(schedule.title) 완료")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(schedule.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(schedule.displayTime)
                .font(.caption)
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
    }

    private var tomorrowButton: some View {
        Button(action: onMoveToTomorrow) {
            Image(systemName: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .frame(width: MemdoMetrics.touchTarget)
                .frame(minHeight: MemdoMetrics.touchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(schedule.title) 내일로 이동")
    }

    private var moreMenu: some View {
        Menu {
            Button("다른 날짜로", systemImage: "calendar", action: onChooseDate)
            Button("삭제", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            MemdoIconButtonLabel(systemImage: "ellipsis")
        }
        .accessibilityLabel("\(schedule.title) 더보기")
    }
}

private struct MoveScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    let schedule: ScheduleDetail
    let onMove: (Date) -> Void

    init(schedule: ScheduleDetail, onMove: @escaping (Date) -> Void) {
        self.schedule = schedule
        self.onMove = onMove
        _selectedDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 1, to: schedule.startAt) ?? schedule.startAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("이동할 일정") {
                    Text(schedule.title)
                    LabeledContent("현재", value: schedule.dateText)
                }
                Section("새 날짜") {
                    DatePicker("날짜", selection: $selectedDate, displayedComponents: .date)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MemdoTheme.background)
            .navigationTitle("일정 이동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("이동") {
                        onMove(selectedDate)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .memdoSheetPresentation([.medium])
    }
}
