import SwiftUI

struct DailySummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var scope = SummaryScope.today
    @State private var pendingDeletion: ScheduleDetail?
    @State private var presentedSheet: SummarySheetDestination?
    @State private var agentComposer = ""
    @State private var agentResponse = ""

    let date: Date

    init(date: Date = .now) {
        self.date = date
    }

    private var tasks: [ScheduleDetail] {
        let interval = scope.interval(endingAt: date)
        return scheduleStore.schedules
            .filter {
                $0.isActive &&
                $0.kind == .task &&
                $0.scheduledDate >= interval.start &&
                $0.scheduledDate < interval.end
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
                    onDelete: { pendingDeletion = $0 }
                )
            } else {
                SummaryHistorySection(status: .completed, schedules: completedTasks)
                SummaryHistorySection(status: .missed, schedules: incompleteTasks)
            }
        }
        .memdoSheetPresentation([.large])
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .agent(let scope):
                AgentSheet(
                    composer: $agentComposer,
                    response: $agentResponse,
                    context: scope.agentContext
                )
            case .move(let schedule):
                MoveScheduleSheet(schedule: schedule) { newDate in
                    scheduleStore.move(id: schedule.id, to: newDate)
                }
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
            Text("일정이 목록에서 삭제됩니다.")
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

private enum SummarySheetDestination: Identifiable {
    case agent(SummaryScope)
    case move(ScheduleDetail)

    var id: String {
        switch self {
        case .agent: "agent"
        case .move(let schedule): "move-\(schedule.id)"
        }
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

    var agentContext: String {
        switch self {
        case .today: "오늘 요약"
        case .week: "지난 7일 회고"
        case .month: "지난 30일 회고"
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
                return completed.isEmpty ? "계획이 필요하면 Agent와 내일의 첫 일정을 정해보세요." : "완료한 흐름을 내일 계획으로 이어갈 수 있어요."
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
            Label("Agent 분석", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoTheme.brand)
            Text(headline)
                .font(.headline)
                .foregroundStyle(MemdoTheme.ink)
            Text(evidence)
                .font(.subheadline)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpenAgent) {
                HStack(spacing: 8) {
                    Text("Agent와 함께 정리")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MemdoTheme.brand)
                .frame(minHeight: MemdoMetrics.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Divider() }
        }
        .padding(.leading, 12)
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
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("완료")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                Spacer(minLength: 0)
                Text("\(max(totalCount - completedCount, 0)) \(incompleteLabel)")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
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
                .memdoRowGroup()
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
