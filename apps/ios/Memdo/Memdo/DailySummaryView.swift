import SwiftUI

struct DailySummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var scope = SummaryScope.today
    @State private var pendingDeletion: ScheduleDetail?
    @State private var presentedSheet: SummarySheetDestination?
    @State private var agentComposer = ""
    @State private var agentMessages: [AgentMessage] = []

    let date: Date

    init(date: Date = .now) {
        self.date = date
    }

    // docs/07 §5's daily-summary target is defined by date/status only --
    // planned/in_progress/partial (isActive), no kind restriction. A
    // `kind == .task` filter here used to silently drop every timed event
    // from the summary (found during founder dogfooding). Extracted as a
    // static func so it's directly unit-testable without a live ScheduleStore.
    nonisolated static func summaryTasks(
        from schedules: [ScheduleDetail],
        interval: DateInterval,
        ascending: Bool
    ) -> [ScheduleDetail] {
        schedules
            .filter {
                $0.isActive &&
                $0.scheduledDate >= interval.start &&
                $0.scheduledDate < interval.end
            }
            .sorted { ascending ? $0.timeSortKey < $1.timeSortKey : $0.timeSortKey > $1.timeSortKey }
    }

    private var tasks: [ScheduleDetail] {
        Self.summaryTasks(
            from: scheduleStore.schedules,
            interval: scope.interval(endingAt: date),
            ascending: scope == .today
        )
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
            eyebrow: scope == .today ? "오늘 돌아보기" : "기록 회고",
            headerActionIcon: "xmark",
            headerActionLabel: "요약 닫기",
            headerAction: { dismiss() },
            bottomClearance: 0
        ) {
            SummaryScopePicker(selection: $scope)
            SummaryProgressLine(
                completedCount: completedTasks.count,
                totalCount: tasks.count,
                incompleteLabel: scope == .today ? "확인" : "놓침"
            )
            SummaryAgentDigest(
                scope: scope,
                completed: completedTasks,
                incomplete: incompleteTasks,
                onOpenAgent: { presentedSheet = .agent(scope) }
            )
            if scope == .today {
                SummaryReviewSection(
                    reviews: incompleteTasks,
                    onComplete: complete,
                    onMoveToTomorrow: moveToTomorrow,
                    onChooseDate: { presentedSheet = .move($0) },
                    onEdit: { presentedSheet = .edit($0) },
                    onDelete: { pendingDeletion = $0 }
                )
                SummaryHistorySection(
                    status: .completed,
                    schedules: completedTasks,
                    onToggleDone: toggleDone,
                    onEdit: { presentedSheet = .edit($0) },
                    onDelete: { pendingDeletion = $0 }
                )
            } else {
                SummaryHistorySection(
                    status: .completed,
                    schedules: completedTasks,
                    onToggleDone: toggleDone,
                    onEdit: { presentedSheet = .edit($0) },
                    onDelete: { pendingDeletion = $0 }
                )
                SummaryHistorySection(
                    status: .missed,
                    schedules: incompleteTasks,
                    onToggleDone: toggleDone,
                    onEdit: { presentedSheet = .edit($0) },
                    onDelete: { pendingDeletion = $0 }
                )
            }
        }
        .memdoSheetPresentation([.large])
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .agent(let scope):
                AgentSheet(
                    composer: $agentComposer,
                    messages: $agentMessages,
                    context: scope.agentContext
                )
            case .move(let schedule):
                MoveScheduleSheet(schedule: schedule) { newDate in
                    Task { try? await scheduleStore.move(id: schedule.id, to: newDate) }
                }
            case .edit(let schedule):
                ScheduleDetailSheet(schedule: schedule, onSave: { edited in Task { try? await scheduleStore.save(edited) } })
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
                if let pendingDeletion {
                    Task { try? await scheduleStore.delete(id: pendingDeletion.id) }
                }
                pendingDeletion = nil
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("일정이 목록에서 삭제됩니다.")
        }
    }

    private func complete(_ schedule: ScheduleDetail) {
        var completed = schedule
        completed.isDone = true
        Task { try? await scheduleStore.save(completed) }
    }

    private func toggleDone(_ schedule: ScheduleDetail) {
        Task { try? await scheduleStore.toggleDone(id: schedule.id) }
    }

    private func moveToTomorrow(_ schedule: ScheduleDetail) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        Task { try? await scheduleStore.move(id: schedule.id, to: tomorrow) }
    }
}

private enum SummarySheetDestination: Identifiable {
    case agent(SummaryScope)
    case move(ScheduleDetail)
    case edit(ScheduleDetail)

    var id: String {
        switch self {
        case .agent: "agent"
        case .move(let schedule): "move-\(schedule.id)"
        case .edit(let schedule): "edit-\(schedule.id)"
        }
    }
}

enum SummaryScope: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "하루 정리"
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

    var agentContext: AgentContext {
        switch self {
        case .today: .todaySummary
        case .week: .weekReview
        case .month: .monthReview
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
            // "지난 7일" means 7 calendar days including today -- start 6
            // days back, end at tomorrow's midnight (exclusive). The
            // previous `end: startOfDay` boundary put today exactly on the
            // excluded edge, so anything scheduled today never appeared
            // here (found during founder dogfooding).
            return DateInterval(
                start: calendar.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay,
                end: calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            )
        case .month:
            return DateInterval(
                start: calendar.date(byAdding: .day, value: -29, to: startOfDay) ?? startOfDay,
                end: calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
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

private struct SummaryAgentDigest: View {
    let scope: SummaryScope
    let completed: [ScheduleDetail]
    let incomplete: [ScheduleDetail]
    let onOpenAgent: () -> Void

    private var headline: String {
        if scope == .today {
            if incomplete.isEmpty {
                return completed.isEmpty ? "오늘은 정리할 작업이 없어요" : "오늘의 작업을 모두 마쳤어요"
            }
            return "\(completed.count)개를 마쳤고 \(incomplete.count)개는 결정을 기다려요"
        }
        if incomplete.isEmpty {
            return "\(completed.count)개를 끝내고 놓친 작업 없이 지나왔어요"
        }
        return "\(completed.count)개를 끝내고 \(incomplete.count)개를 놓쳤어요"
    }

    private var evidence: String {
        if scope == .today {
            guard let next = incomplete.first else {
                return completed.isEmpty ? "빈 시간에 새 일정을 추가해보세요." : "완료한 흐름을 내일 계획으로 이어갈 수 있어요."
            }
            return "먼저 확인할 작업은 ‘\(next.title)’이에요. 아래에서 완료하거나 날짜를 다시 정할 수 있어요."
        }

        let done = completed.prefix(2).map(\.title).joined(separator: " · ")
        let missed = incomplete.prefix(2).map(\.title).joined(separator: " · ")
        switch (done.isEmpty, missed.isEmpty) {
        case (false, false): return "완료 흐름: \(done). 다시 볼 일: \(missed)."
        case (false, true): return "완료 흐름: \(done). 놓치고 지난 작업은 없어요."
        case (true, false): return "다시 볼 일: \(missed). 다음 계획에서 시간을 다시 잡아보세요."
        case (true, true): return "분석할 작업 기록이 아직 없어요."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("일정 분석", systemImage: "chart.bar.fill")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.brand)
            Text(headline)
                .font(MemdoTypography.sectionTitle)
                .foregroundStyle(MemdoTheme.ink)
            Text(evidence)
                .font(MemdoTypography.subtitle)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpenAgent) {
                Label("더 살펴보기", systemImage: "arrow.up.right")
                    .font(MemdoTypography.action)
            }
            .buttonStyle(.bordered)
            .tint(MemdoTheme.brand)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 2)
            .overlay(alignment: .top) { Divider() }
        }
        .padding(.leading, MemdoMetrics.rowInset)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(MemdoTheme.brand)
                .frame(width: 3)
        }
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
                Text("\(completedCount)/\(totalCount)")
                    .font(MemdoTypography.action)
                    .monospacedDigit()
                Text("완료")
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                Spacer(minLength: 0)
                Text("\(max(totalCount - completedCount, 0)) \(incompleteLabel)")
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            ProgressView(value: totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount))
                .tint(MemdoTheme.brand)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    let status: SummaryHistoryStatus
    let schedules: [ScheduleDetail]
    let onToggleDone: (ScheduleDetail) -> Void
    let onEdit: (ScheduleDetail) -> Void
    let onDelete: (ScheduleDetail) -> Void

    private var visibleSchedules: [ScheduleDetail] {
        Array(schedules.prefix(isExpanded ? schedules.count : 3))
    }

    var body: some View {
        MemdoSection(title: status.title, trailing: "\(schedules.count)개") {
            if schedules.isEmpty {
                MemdoStatusRow(
                    title: status == .completed ? "완료 기록이 없어요" : "놓친 작업이 없어요",
                    systemImage: status.systemImage
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleSchedules) { schedule in
                        SummaryHistoryRow(
                            schedule: schedule,
                            status: status,
                            onToggleDone: { onToggleDone(schedule) },
                            onEdit: { onEdit(schedule) },
                            onDelete: { onDelete(schedule) }
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
                            action: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { isExpanded.toggle() } }
                        )
                    }
                }
                .memdoRowGroup()
            }
        }
    }
}

private struct SummaryHistoryRow: View {
    let schedule: ScheduleDetail
    let status: SummaryHistoryStatus
    let onToggleDone: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: MemdoMetrics.rowSpacing) {
            Button(action: onToggleDone) {
                Image(systemName: schedule.isDone ? "checkmark.circle.fill" : "circle")
                    .font(MemdoTypography.title3)
                    .foregroundStyle(schedule.isDone ? MemdoTheme.secondaryInk : MemdoTheme.brand)
                    .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(schedule.isDone ? "\(schedule.title) 완료 취소" : "\(schedule.title) 완료로 표시")
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.title)
                    .font(MemdoTypography.action)
                    .lineLimit(2)
                Text("\(schedule.dateText) · \(schedule.displayTime)")
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Row-level .combine was removed when the toggle/menu became
            // separately focusable, but that also merged title+subtitle into
            // one VoiceOver stop -- scope .combine to just this block so
            // that pairing survives without re-merging the whole row.
            .accessibilityElement(children: .combine)
            Menu {
                Button("편집", systemImage: "pencil", action: onEdit)
                Button("삭제", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                MemdoIconButtonLabel(systemImage: "ellipsis")
            }
            .accessibilityLabel("\(schedule.title) 더보기")
        }
        .padding(.horizontal, MemdoMetrics.rowInset)
        .padding(.vertical, 4)
    }
}

private struct SummaryReviewSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    let reviews: [ScheduleDetail]
    let onComplete: (ScheduleDetail) -> Void
    let onMoveToTomorrow: (ScheduleDetail) -> Void
    let onChooseDate: (ScheduleDetail) -> Void
    let onEdit: (ScheduleDetail) -> Void
    let onDelete: (ScheduleDetail) -> Void

    private var visibleReviews: [ScheduleDetail] {
        Array(reviews.prefix(isExpanded ? reviews.count : 3))
    }

    var body: some View {
        MemdoSection(title: "결정이 필요한 일정", trailing: "\(reviews.count)개") {
            if reviews.isEmpty {
                MemdoStatusRow(
                    title: "정리가 끝났어요",
                    systemImage: "checkmark.circle.fill",
                    detail: "결정이 필요한 일정이 없어요."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleReviews) { schedule in
                        SummaryReviewRow(
                            schedule: schedule,
                            onComplete: { onComplete(schedule) },
                            onMoveToTomorrow: { onMoveToTomorrow(schedule) },
                            onChooseDate: { onChooseDate(schedule) },
                            onEdit: { onEdit(schedule) },
                            onDelete: { onDelete(schedule) }
                        )
                        if schedule.id != visibleReviews.last?.id {
                            Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                        }
                    }
                    if reviews.count > 3 {
                        Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                        MemdoDisclosureRow(
                            isExpanded: isExpanded,
                            hiddenCount: reviews.count - 3,
                            totalCount: reviews.count,
                            action: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { isExpanded.toggle() } }
                        )
                    }
                }
                .memdoRowGroup()
            }
        }
    }
}

private struct SummaryReviewRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let schedule: ScheduleDetail
    let onComplete: () -> Void
    let onMoveToTomorrow: () -> Void
    let onChooseDate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: MemdoMetrics.rowSpacing) {
                        completeButton
                        titleBlock
                    }
                    HStack(spacing: 8) {
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
                .font(MemdoTypography.title3)
                .foregroundStyle(MemdoTheme.brand)
                .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(schedule.title) 완료")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(schedule.title)
                .font(MemdoTypography.action)
                .lineLimit(2)
            Text(schedule.displayTime)
                .font(MemdoTypography.caption)
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
    }

    private var tomorrowButton: some View {
        Button(action: onMoveToTomorrow) {
            Label("내일", systemImage: "calendar.badge.clock")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(minHeight: MemdoMetrics.touchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(schedule.title) 내일로 이동")
    }

    private var moreMenu: some View {
        Menu {
            Button("편집", systemImage: "pencil", action: onEdit)
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
        _selectedDate = State(
            initialValue: Calendar.current.date(byAdding: .day, value: 1, to: schedule.scheduledDate)
                ?? schedule.scheduledDate
        )
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
            .memdoSystemList()
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
