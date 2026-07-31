import SwiftUI

enum AppTab: String, CaseIterable {
    case today
    case calendar
    case search
    case assistant
    case settings

    var title: String {
        switch self {
        case .today: "오늘"
        case .calendar: "캘린더"
        case .search: "검색"
        case .assistant: "AI"
        case .settings: "설정"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .search: "magnifyingglass"
        case .assistant: "sparkles"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct AppShellView: View {
    @State private var selectedTab = AppTab.today

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tag(AppTab.today)
            CalendarView()
                .tag(AppTab.calendar)
            ScheduleSearchView()
                .tag(AppTab.search)
            AssistantView()
                .tag(AppTab.assistant)
            SettingsView()
                .tag(AppTab.settings)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selectedTab)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
        .tint(MemdoTheme.accent)
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? MemdoTheme.accent : MemdoTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        selection == tab ? MemdoTheme.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: MemdoTheme.ink.opacity(0.10), radius: 16, y: 7)
    }
}

struct CalendarView: View {
    private let days = Array(1...31)

    var body: some View {
        MemdoPage(title: "캘린더", subtitle: "2026년 7월", eyebrow: "나의 시간", icon: "calendar") {
            VStack(spacing: 18) {
                HStack {
                    Text("7월")
                        .font(.title3.bold())
                    Spacer()
                    Button("오늘") {}
                        .buttonStyle(.bordered)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                    ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) {
                        Text($0).font(.caption.bold()).foregroundStyle(MemdoTheme.secondaryInk)
                    }
                    ForEach(days, id: \.self) { day in
                        Text("\(day)")
                            .font(.subheadline.weight(day == 31 ? .bold : .regular))
                            .foregroundStyle(day == 31 ? .white : MemdoTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(day == 31 ? MemdoTheme.accent : .clear, in: Circle())
                            .overlay(alignment: .bottom) {
                                if [3, 8, 15, 23].contains(day) {
                                    Circle().fill(MemdoTheme.accent).frame(width: 3, height: 3)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            SectionTitle(title: "7월 31일", trailing: "7개")
            VStack(spacing: 0) {
                AgendaRow(time: "10:00", title: "앱 기획 문서 다듬기", source: "내 일정")
                Divider().padding(.leading, 72)
                AgendaRow(time: "14:30", title: "디자인 시안 확인", source: "Google")
                Divider().padding(.leading, 72)
                AgendaRow(time: "19:00", title: "30분 산책", source: "내 일정")
            }
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button {
            } label: {
                Label("4개 일정 더 보기", systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct ScheduleSearchView: View {
    @State private var query = "디자인"

    var body: some View {
        MemdoPage(title: "검색", subtitle: "내 기억 속 일정을 찾아보세요", eyebrow: "기억 탐색", icon: "magnifyingglass") {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                TextField("일정, 메모, 장소", text: $query)
                Image(systemName: "mic")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(MemdoTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MemdoTheme.outline))

            HStack(spacing: 8) {
                FilterPill(title: "전체", selected: true)
                FilterPill(title: "내 일정", selected: false)
                FilterPill(title: "Google", selected: false)
                Spacer()
            }

            SectionTitle(title: "검색 결과", trailing: "3개")
            VStack(spacing: 0) {
                SearchResult(date: "7월 31일 · 14:30", title: "디자인 시안 확인", note: "Google Calendar")
                Divider().padding(.leading, 58)
                SearchResult(date: "7월 24일 · 11:00", title: "위젯 디자인 리뷰", note: "완료됨")
                Divider().padding(.leading, 58)
                SearchResult(date: "7월 18일 · 16:00", title: "디자인 시스템 정리", note: "내 일정")
            }
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button {
            } label: {
                Label("AI에게 이 일정들 요약 요청", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct AssistantView: View {
    var body: some View {
        MemdoPage(title: "AI 도우미", subtitle: "확인 전에는 일정을 변경하지 않아요", eyebrow: "조용한 도우미", icon: "sparkles") {
            ChatBubble(text: "매주 화요일 오후에 운동 일정을 만들어줘.", isUser: true)
            ChatBubble(text: "오후 7시부터 1시간으로 제안할게요. 8월부터 매주 반복할까요?", isUser: false)

            VStack(alignment: .leading, spacing: 16) {
                Label("반복 일정 제안", systemImage: "calendar.badge.plus")
                    .font(.headline)
                LabeledContent("제목", value: "운동")
                LabeledContent("시간", value: "매주 화요일 19:00")
                LabeledContent("알림", value: "30분 전")
                Divider()
                HStack {
                    Button("수정") {}
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("일정에 추가") {}
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [MemdoTheme.accentSoft, MemdoTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )

            HStack(spacing: 10) {
                TextField("무엇을 도와드릴까요?", text: .constant(""))
                Button {} label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("보내기")
            }
            .padding(8)
            .background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(MemdoTheme.outline))
        }
    }
}

struct DailySummaryView: View {
    var body: some View {
        MemdoPage(title: "오늘 요약", subtitle: "7월 31일 금요일 · 21:30", eyebrow: "하루 마무리", icon: "moon.stars") {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(MemdoTheme.outline, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: 0.34)
                        .stroke(MemdoTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("1/3").font(.title3.bold())
                        Text("완료").font(.caption2)
                    }
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 6) {
                    Text("핵심 한 가지를 끝냈어요")
                        .font(.title3.bold())
                    Text("남은 일정은 지금 결정하고 내일을 가볍게 시작해요.")
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [MemdoTheme.mineSoft, MemdoTheme.surface],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )

            SectionTitle(title: "결정이 필요한 일정", trailing: "2개")
            VStack(spacing: 0) {
                ReviewRow(title: "디자인 시안 확인", time: "14:30")
                Divider().padding(.leading, 16)
                ReviewRow(title: "30분 산책", time: "19:00")
            }
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Label("AI가 본 오늘", systemImage: "sparkles")
                    .font(.headline)
                Text("오전에는 계획한 일에 집중했지만 오후 일정이 밀렸어요. 내일은 중요한 확인 업무를 오전으로 옮겨보세요.")
                    .foregroundStyle(MemdoTheme.secondaryInk)
                Label("내일 10:00으로 이동 추천", systemImage: "arrow.forward.circle.fill")
                    .font(.caption.bold())
            }
            .padding(16)
            .background(MemdoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 24))

            Button("정리 완료") {}
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }
}

struct SettingsView: View {
    @State private var dailySummary = true
    @State private var calendarSync = true

    var body: some View {
        MemdoPage(title: "설정", subtitle: "Memdo를 나에게 맞게 조정하세요", eyebrow: "나만의 Memdo", icon: "slider.horizontal.3") {
            SettingsGroup(title: "하루") {
                Toggle("오늘 요약 받기", isOn: $dailySummary)
                Divider()
                LabeledContent("요약 시간", value: "21:30")
                Divider()
                LabeledContent("계획이 없을 때", value: "아침 9시")
            }

            SettingsGroup(title: "연결 및 권한") {
                Toggle("Google Calendar", isOn: $calendarSync)
                Divider()
                LabeledContent("AI 데이터 접근", value: "일정 제목·시간")
                Divider()
                LabeledContent("알림", value: "허용됨")
            }

            SettingsGroup(title: "관심 뉴스") {
                HStack {
                    FilterPill(title: "AI", selected: true)
                    FilterPill(title: "생산성", selected: true)
                    FilterPill(title: "로컬", selected: false)
                }
            }
        }
    }
}

private struct MemdoPage<Content: View>: View {
    let title: String
    let subtitle: String
    let eyebrow: String
    let icon: String
    @ViewBuilder let content: Content

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MemdoTheme.accent)
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                Spacer(minLength: 8)

                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MemdoTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(MemdoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            content
        }
        .padding(20)
        .padding(.bottom, 28)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MemdoPageBackground()
                ScrollView {
                    pageContent
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(MemdoTheme.accent)
    }
}

private struct SectionTitle: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            Text(trailing).font(.caption.bold()).foregroundStyle(MemdoTheme.secondaryInk)
        }
    }
}

private struct AgendaRow: View {
    let time: String
    let title: String
    let source: String

    var body: some View {
        HStack(spacing: 14) {
            Text(time)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(width: 46, alignment: .leading)
            Image(systemName: source == "Google" ? "calendar" : "person.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(source == "Google" ? MemdoTheme.google : MemdoTheme.mine)
                .frame(width: 34, height: 34)
                .background(
                    source == "Google" ? MemdoTheme.googleSoft : MemdoTheme.mineSoft,
                    in: RoundedRectangle(cornerRadius: 10)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.bold())
                Label(source, systemImage: source == "Google" ? "calendar" : "person.fill")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

private struct FilterPill: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(selected ? .white : MemdoTheme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(selected ? MemdoTheme.accent : MemdoTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(MemdoTheme.outline))
    }
}

private struct SearchResult: View {
    let date: String
    let title: String
    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.contains("Google") ? "calendar" : "clock.arrow.circlepath")
                .foregroundStyle(note.contains("Google") ? MemdoTheme.google : MemdoTheme.accent)
                .frame(width: 34, height: 34)
                .background(
                    note.contains("Google") ? MemdoTheme.googleSoft : MemdoTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 10)
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(date).font(.caption).foregroundStyle(MemdoTheme.secondaryInk)
                Text(title).font(.headline)
                Text(note).font(.caption).foregroundStyle(MemdoTheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private struct ChatBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(isUser ? .white : MemdoTheme.ink)
            .padding(14)
            .background(
                isUser ? MemdoTheme.accent : MemdoTheme.accentSoft,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .frame(maxWidth: 310, alignment: isUser ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct ReviewRow: View {
    let title: String
    let time: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.bold())
                    Text(time).font(.caption).foregroundStyle(MemdoTheme.secondaryInk)
                }
                Spacer()
            }
            HStack {
                Button("완료") {}
                Button("내일로") {}
                Spacer()
                Button(role: .destructive) {} label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("일정 삭제")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            VStack(spacing: 14) { content }
                .padding(16)
                .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

private extension View {
    func memdoCard() -> some View {
        background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
