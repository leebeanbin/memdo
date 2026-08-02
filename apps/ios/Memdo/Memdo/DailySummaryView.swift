import SwiftUI

struct DailySummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var pendingDeletion: ScheduleDetail?
    @State private var pendingMove: ScheduleDetail?

    let date: Date

    init(date: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 31)) ?? .now) {
        self.date = date
    }

    private var tasks: [ScheduleDetail] {
        scheduleStore.items(for: date).filter { $0.kind == .task }
    }

    private var reviews: [ScheduleDetail] {
        tasks.filter { !$0.isDone }
    }

    var body: some View {
        MemdoPage(
            title: "오늘 요약",
            subtitle: date.formatted(
                .dateTime
                    .month(.wide)
                    .day()
                    .weekday(.wide)
                    .locale(Locale(identifier: "ko_KR"))
            ),
            eyebrow: "하루 마무리",
            headerActionIcon: "xmark",
            headerActionLabel: "오늘 요약 닫기",
            headerAction: { dismiss() }
        ) {
            SummaryProgressLine(completedCount: tasks.count - reviews.count, totalCount: tasks.count)
            SummaryInsightSection(remainingCount: reviews.count)
            SummaryReviewSection(
                reviews: reviews,
                onComplete: complete,
                onMoveToTomorrow: moveToTomorrow,
                onChooseDate: { pendingMove = $0 },
                onDelete: { pendingDeletion = $0 }
            )
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

private struct SummaryProgressLine: View {
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("완료 \(completedCount)")
                    .font(.subheadline.weight(.semibold))
                Text("확인 \(max(totalCount - completedCount, 0))")
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
