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
            subtitle: date.formatted(.dateTime.month(.wide).day().weekday(.wide)),
            eyebrow: "하루 마무리"
        ) {
            SummaryProgressLine(completedCount: tasks.count - reviews.count, totalCount: tasks.count)
            SummaryReviewSection(
                reviews: reviews,
                onComplete: complete,
                onMoveToTomorrow: moveToTomorrow,
                onChooseDate: { pendingMove = $0 },
                onDelete: { pendingDeletion = $0 }
            )
            SummaryInsightSection(remainingCount: reviews.count)
            Button { dismiss() } label: {
                MemdoButtonLabel("정리 완료", fillsWidth: true)
            }
            .buttonStyle(.borderedProminent)
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
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MemdoTheme.brand)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent가 정리한 오늘")
                    .font(.subheadline.weight(.semibold))
                Text("완료 \(completedCount)개 · 결정 필요 \(max(totalCount - completedCount, 0))개")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            Spacer(minLength: 0)
            Text("\(completedCount)/\(totalCount)")
                .font(.subheadline.monospacedDigit().weight(.bold))
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
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .memdoCard()
            }
        }
    }
}

private struct SummaryInsightSection: View {
    let remainingCount: Int

    var body: some View {
        MemdoSection(title: "Agent 메모") {
            VStack(alignment: .leading, spacing: 8) {
                Text(remainingCount == 0
                     ? "오늘의 할 일을 모두 정리했어요."
                     : "남은 \(remainingCount)개 중 중요한 일만 날짜를 다시 정하고, 나머지는 완료 여부를 확인해 보세요.")
                    .font(.subheadline)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                if remainingCount > 0 {
                    Label("이동 전 날짜를 직접 확인해요", systemImage: "calendar.badge.clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MemdoTheme.accent)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.title).font(.body.bold())
                    Text(schedule.displayTime).font(.caption).foregroundStyle(MemdoTheme.secondaryInk)
                }
                Spacer()
            }
            reviewActionLayout {
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button(action: onComplete) {
                    MemdoButtonLabel("완료", systemImage: "checkmark", size: actionSize)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onMoveToTomorrow) {
                    MemdoButtonLabel("내일로", systemImage: "arrow.forward", size: actionSize)
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("다른 날짜로", systemImage: "calendar", action: onChooseDate)
                    Button("삭제", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    MemdoIconButtonLabel(systemImage: "ellipsis")
                }
                .accessibilityLabel("일정 더보기")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var actionSize: MemdoButtonLabel.Size {
        dynamicTypeSize.isAccessibilitySize ? .regular : .compact
    }

    private var reviewActionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 6))
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
