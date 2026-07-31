import SwiftUI

struct TodayView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var presentedSheet: SheetDestination?
    @State private var selectedDate = 31
    @State private var briefingMessage = ""

    private var schedules: [ScheduleDetail] {
        scheduleStore.items(for: selectedDate)
    }

    private var completedCount: Int {
        schedules.filter(\.isDone).count
    }

    private var remainingCount: Int {
        schedules.count - completedCount
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MemdoPageBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        weekIndex
                        if schedules.isEmpty {
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
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .addTask(let day):
                    AddScheduleSheet(day: day, onSave: scheduleStore.save)
                case .dailySummary:
                    DailySummaryView()
                case .detail(let schedule):
                    ScheduleDetailSheet(schedule: schedule, onSave: scheduleStore.save)
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
                Text(selectedDate == 31 ? "좋은 오후예요" : selectedDate < 31 ? "지난 하루" : "다가오는 하루")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MemdoTheme.accent)
                Text(selectedDate == 31 ? "오늘" : selectedDate > 31 ? "8월 \(displayDate(selectedDate))일" : "7월 \(selectedDate)일")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(MemdoTheme.ink)
                Text(dateSubtitle)
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
                        .trim(from: 0, to: schedules.isEmpty ? 0 : CGFloat(completedCount) / CGFloat(schedules.count))
                        .stroke(MemdoTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(completedCount)/\(schedules.count)")
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
        .memdoCard(radius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 1)
        }
    }

    private func displayDate(_ date: Int) -> String {
        String(date > 31 ? date - 31 : date)
    }

    private var dateSubtitle: String {
        let weekday = ["27": "월요일", "28": "화요일", "29": "수요일", "30": "목요일", "31": "금요일", "32": "토요일", "33": "일요일"]["\(selectedDate)"] ?? ""
        let month = selectedDate > 31 ? 8 : 7
        return "\(month)월 \(displayDate(selectedDate))일 \(weekday)"
    }

    private var intention: some View {
        Button {
            presentedSheet = .addTask(selectedDate)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("오늘의 방향", systemImage: "sparkle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MemdoTheme.peach)
                    Text(selectedDate == 31 ? "오늘은 어떤 하루를 보내고 싶나요?" : "이날에는 어떤 시간을 보내고 싶나요?")
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
            MemdoSectionHeader(title: "일정", trailing: "\(remainingCount)개 남음")

            VStack(spacing: 0) {
                ForEach(schedules) { schedule in
                    ScheduleRow(
                        schedule: schedule,
                        context: .timeline,
                        onOpen: { presentedSheet = .detail(schedule) },
                        onToggleDone: { scheduleStore.toggleDone(id: schedule.id) }
                    )
                    if schedule.id != schedules.last?.id {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .padding(.vertical, 4)
            .memdoCard()
        }
    }

    private var briefing: some View {
        VStack(alignment: .leading, spacing: 14) {
            MemdoSectionHeader(title: "3분 브리핑", trailing: "AI 요약")

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
                    Text("\(selectedDate == 31 ? "오늘" : "선택한 날") \(completedCount)/\(schedules.count) 완료")
                        .font(.subheadline.weight(.semibold))
                    Text(schedules.isEmpty ? "등록된 일정이 없어요" : remainingCount == 0 ? "모든 일정을 정리했어요" : "남은 \(remainingCount)개를 확인해 보세요")
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
            presentedSheet = .addTask(selectedDate)
        } label: {
            Label("새 일정", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 22)
                .frame(minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }

    private func briefingButton(icon: String, title: String, summary: String) -> some View {
        Button {
            briefingMessage = "\(title)\n\n\(summary)"
        } label: {
            BriefingRow(icon: icon, title: title, summary: summary)
        }
        .buttonStyle(.plain)
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

private enum SheetDestination: Identifiable {
    case addTask(Int)
    case dailySummary
    case detail(ScheduleDetail)

    var id: String {
        switch self {
        case .addTask(let day): "addTask-\(day)"
        case .dailySummary: "dailySummary"
        case .detail(let schedule): "detail-\(schedule.id)"
        }
    }
}

struct TodayView_Previews: PreviewProvider {
    static var previews: some View {
        TodayView()
            .environment(ScheduleStore())
    }
}
