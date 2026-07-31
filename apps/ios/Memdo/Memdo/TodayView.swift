import SwiftUI

struct TodayView: View {
    @State private var tasks = DayTask.samples
    @State private var presentedSheet: SheetDestination?
    @State private var selectedDate = 31
    @State private var briefingMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MemdoPageBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        weekIndex
                        if tasks.isEmpty {
                            intention
                        } else {
                            schedule
                        }
                        briefing
                        summary
                        HStack {
                            Spacer()
                            addButton
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .addTask:
                    AddTaskSheet { title, time in
                        tasks.append(.init(title: title, time: time, source: .mine))
                    }
                case .dailySummary:
                    DailySummaryView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("3분 브리핑", isPresented: Binding(
                get: { !briefingMessage.isEmpty },
                set: { if !$0 { briefingMessage = "" } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(briefingMessage)
            }
        }
        .tint(MemdoTheme.accent)
        .sensoryFeedback(.selection, trigger: selectedDate)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("좋은 오후예요")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MemdoTheme.accent)
                Text("오늘")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(MemdoTheme.ink)
                Text("7월 31일 금요일")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }

            Spacer()

            Button {
                presentedSheet = .dailySummary
            } label: {
                ZStack {
                    Circle()
                        .stroke(MemdoTheme.accent.opacity(0.16), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: tasks.isEmpty ? 0 : CGFloat(tasks.filter(\.isDone).count) / CGFloat(tasks.count))
                        .stroke(MemdoTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(tasks.filter(\.isDone).count)/\(tasks.count)")
                            .font(.caption.weight(.bold))
                        Text("완료")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MemdoTheme.secondaryInk)
                    }
                }
                .frame(width: 56, height: 56)
                .foregroundStyle(MemdoTheme.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("오늘 완료 현황")
        }
    }

    private var weekIndex: some View {
        HStack(spacing: 4) {
            ForEach(Array(zip(["월", "화", "수", "목", "금", "토", "일"], 27...33)), id: \.0) { day, date in
                Button {
                    selectedDate = date
                } label: {
                    VStack(spacing: 4) {
                        Text(day)
                            .font(.caption2.weight(.semibold))
                        Text(displayDate(date))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(date == selectedDate ? Color.white : MemdoTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(date == selectedDate ? MemdoTheme.accent : Color.clear)
                    .clipShape(Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(day)요일 \(displayDate(date))일")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 1)
        }
    }

    private func displayDate(_ date: Int) -> String {
        String(date > 31 ? date - 31 : date)
    }

    private var intention: some View {
        Button {
            presentedSheet = .addTask
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("오늘의 방향", systemImage: "sparkle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MemdoTheme.peach)
                    Text("오늘은 어떤 하루를 보내고 싶나요?")
                        .font(.headline)
                        .foregroundStyle(MemdoTheme.ink)
                    Text("계획이 비어 있을 때 가볍게 시작해보세요")
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MemdoTheme.peach)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.7), in: Circle())
            }
            .multilineTextAlignment(.leading)
            .padding(18)
            .background(
                LinearGradient(
                    colors: [MemdoTheme.peachSoft, MemdoTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("일정", trailing: "\(tasks.filter { !$0.isDone }.count)개 남음")

            VStack(spacing: 0) {
                ForEach($tasks) { $task in
                    TimelineTaskRow(task: $task)
                    if task.id != tasks.last?.id {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var briefing: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("3분 브리핑", trailing: "AI 요약")

            VStack(spacing: 0) {
                briefingButton(
                    icon: "cpu",
                    title: "온디바이스 AI 도구 확대",
                    summary: "개인정보를 기기 안에서 처리하는 흐름이 커지고 있어요."
                )
                Divider().padding(.leading, 60)
                briefingButton(
                    icon: "checklist",
                    title: "생산성 앱은 회고 중심으로",
                    summary: "완벽한 계획보다 미완료 일정을 정리하는 경험에 집중해요."
                )
                Divider().padding(.leading, 60)
                briefingButton(
                    icon: "cloud.rain",
                    title: "퇴근 무렵 짧은 소나기",
                    summary: "19시 산책은 30분 정도 늦추는 편이 좋아요."
                )
            }
            .background(MemdoTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var summary: some View {
        Button {
            presentedSheet = .dailySummary
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(MemdoTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(MemdoTheme.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("오늘 1/3 완료")
                        .font(.subheadline.weight(.semibold))
                    Text("남은 2개를 정리하면 하루가 끝나요")
                        .font(.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .foregroundStyle(MemdoTheme.ink)
            .padding(18)
            .background(
                LinearGradient(
                    colors: [MemdoTheme.accentSoft, MemdoTheme.surface],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
            presentedSheet = .addTask
        } label: {
            Label("새 일정", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 22)
                .frame(minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .shadow(color: MemdoTheme.ink.opacity(0.12), radius: 12, y: 5)
    }

    private func briefingButton(icon: String, title: String, summary: String) -> some View {
        Button {
            briefingMessage = "\(title)\n\n\(summary)"
        } label: {
            BriefingRow(icon: icon, title: title, summary: summary)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(MemdoTheme.ink)
            Spacer()
            Text(trailing)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
    }
}

private struct TimelineTaskRow: View {
    @Binding var task: DayTask

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(task.time)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(width: 48, alignment: .leading)

            Image(systemName: task.source == .mine ? "person.fill" : "calendar")
                .font(.caption.weight(.bold))
                .foregroundStyle(task.source == .mine ? MemdoTheme.mine : MemdoTheme.google)
                .frame(width: 34, height: 34)
                .background(
                    task.source == .mine ? MemdoTheme.mineSoft : MemdoTheme.googleSoft,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? MemdoTheme.secondaryInk : MemdoTheme.ink)

                Text(task.source.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }

            Spacer(minLength: 0)

            Button {
                task.isDone.toggle()
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "완료 취소" : "완료로 표시")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct BriefingRow: View {
    let icon: String
    let title: String
    let summary: String

    private var iconColor: Color {
        switch icon {
        case "cpu": MemdoTheme.accent
        case "checklist": MemdoTheme.mine
        default: MemdoTheme.google
        }
    }

    private var iconBackground: Color {
        switch icon {
        case "cpu": MemdoTheme.accentSoft
        case "checklist": MemdoTheme.mineSoft
        default: MemdoTheme.googleSoft
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MemdoTheme.ink)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var time = Date()

    let onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("무엇을 할까요?") {
                    TextField("예: 산책하며 생각 정리하기", text: $title)
                    DatePicker("시간", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("새 일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") {
                        onSave(title, time.formatted(date: .omitted, time: .shortened))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private enum SheetDestination: String, Identifiable {
    case addTask
    case dailySummary
    var id: String { rawValue }
}

private struct DayTask: Identifiable {
    enum Source {
        case mine
        case google

        var label: String { self == .mine ? "내 일정" : "Google Calendar" }
    }

    let id = UUID()
    var title: String
    var time: String
    var source: Source
    var isDone = false

    static let samples = [
        DayTask(title: "앱 기획 문서 다듬기", time: "10:00", source: .mine),
        DayTask(title: "디자인 시안 확인", time: "14:30", source: .google),
        DayTask(title: "30분 산책", time: "19:00", source: .mine)
    ]
}

struct TodayView_Previews: PreviewProvider {
    static var previews: some View {
        TodayView()
    }
}
