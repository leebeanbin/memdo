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
    @State private var scheduleStore = ScheduleStore()
    @State private var selectedTab = AppTab.today
    @State private var showSummary = false

    var body: some View {
        ZStack {
            tabScreen(.today) { TodayView() }
            tabScreen(.calendar) { CalendarView() }
            tabScreen(.search) { ScheduleSearchView() }
            tabScreen(.assistant) { AssistantView() }
            tabScreen(.settings) { SettingsView() }
        }
        .environment(scheduleStore)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomTabDock(selection: $selectedTab)
        }
        .tint(MemdoTheme.accent)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onOpenURL { url in
            switch url.host {
            case "calendar": selectedTab = .calendar
            case "search": selectedTab = .search
            case "assistant": selectedTab = .assistant
            case "settings": selectedTab = .settings
            case "summary": showSummary = true
            default: selectedTab = .today
            }
        }
        .sheet(isPresented: $showSummary) {
            DailySummaryView()
        }
    }

    private func tabScreen<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }
}

struct BottomTabDock: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Divider()
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
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selection == tab ? MemdoTheme.accent : MemdoTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            selection == tab ? MemdoTheme.accentSoft : Color.clear,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 7)
            .padding(.bottom, 6)
        }
        .background(MemdoTheme.surface.ignoresSafeArea())
    }
}

struct CalendarView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    private let days = Array(1...31)
    @State private var selectedDay = 31
    @State private var showAll = false
    @State private var presentedDay: SelectedCalendarDay?
    @State private var selectedSchedule: ScheduleDetail?

    private var selectedAgenda: [ScheduleDetail] {
        scheduleStore.items(for: selectedDay)
    }

    var body: some View {
        MemdoPage(title: "캘린더", subtitle: "2026년 7월", eyebrow: "나의 시간", icon: "calendar") {
            VStack(spacing: 18) {
                HStack {
                    Text("7월")
                        .font(.title3.bold())
                    Spacer()
                    Button("오늘") {
                        selectedDay = 31
                        showAll = false
                        presentedDay = .init(day: 31)
                    }
                        .buttonStyle(.bordered)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                    ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) {
                        Text($0).font(.caption.bold()).foregroundStyle(MemdoTheme.secondaryInk)
                    }
                    ForEach(days, id: \.self) { day in
                        Button {
                            selectedDay = day
                            showAll = false
                            presentedDay = .init(day: day)
                        } label: {
                            Text("\(day)")
                                .font(.subheadline.weight(day == selectedDay ? .bold : .regular))
                                .foregroundStyle(day == selectedDay ? .white : MemdoTheme.ink)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(day == selectedDay ? MemdoTheme.accent : .clear, in: Circle())
                                .overlay(alignment: .bottom) {
                                    if !scheduleStore.items(for: day).isEmpty {
                                        Circle().fill(MemdoTheme.accent).frame(width: 3, height: 3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .memdoCard()

            MemdoSectionHeader(title: "7월 \(selectedDay)일", trailing: "\(selectedAgenda.count)개")
            if !selectedAgenda.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(selectedAgenda.prefix(showAll ? selectedAgenda.count : 3).enumerated()), id: \.element.id) { index, item in
                        ScheduleRow(schedule: item, context: .timeline) {
                            selectedSchedule = item
                        }
                        if index < min(showAll ? selectedAgenda.count : 3, selectedAgenda.count) - 1 {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .memdoCard()

                if selectedAgenda.count > 3 {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showAll.toggle() }
                    } label: {
                        Label(showAll ? "일정 접기" : "\(selectedAgenda.count - 3)개 일정 더 보기", systemImage: showAll ? "chevron.up.circle" : "ellipsis.circle")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView("등록된 일정이 없어요", systemImage: "calendar.badge.plus", description: Text("빈 시간을 눌러 나만의 일정을 추가해 보세요."))
            }
        }
        .sheet(item: $presentedDay) { selection in
            DayAgendaSheet(day: selection.day)
        }
        .sheet(item: $selectedSchedule) { schedule in
            ScheduleDetailSheet(schedule: schedule, onSave: scheduleStore.save)
        }
    }
}

struct ScheduleSearchView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var query = "디자인"
    @State private var scope = "전체"
    @State private var status = "전체 상태"
    @State private var period = "전체 기간"
    @State private var presentedSearchSheet: SearchSheet?
    @State private var showSummary = false
    @State private var showVoiceHelp = false

    private var filteredResults: [ScheduleDetail] {
        scheduleStore.schedules.filter {
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) &&
            (scope == "전체" || (scope == "Google" ? $0.source.contains("Google") : $0.source == "내 일정")) &&
            (status == "전체 상태" || (status == "완료" ? $0.isDone : !$0.isDone)) &&
            (period == "전체 기간" || (period == "이번 주" ? $0.day >= 27 : $0.day >= 18))
        }
        .sorted { ($0.day, $0.time) > ($1.day, $1.time) }
    }

    var body: some View {
        MemdoPage(title: "검색", subtitle: "내 기억 속 일정을 찾아보세요", eyebrow: "기억 탐색", icon: "magnifyingglass") {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                TextField("일정, 메모, 장소", text: $query)
                Button { showVoiceHelp = true } label: {
                    Image(systemName: "mic")
                }
                .accessibilityLabel("음성 검색")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(MemdoTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MemdoTheme.outline))

            HStack(spacing: 8) {
                ForEach(["전체", "내 일정", "Google"], id: \.self) { item in
                    Button { scope = item } label: {
                        FilterPill(title: item, selected: scope == item)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    presentedSearchSheet = .filters
                } label: {
                    Label("필터", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            if status != "전체 상태" || period != "전체 기간" {
                Text([status, period].filter { $0 != "전체 상태" && $0 != "전체 기간" }.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MemdoTheme.accent)
            }

            MemdoSectionHeader(title: "검색 결과", trailing: "\(filteredResults.count)개")
            if filteredResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredResults) { item in
                        ScheduleRow(schedule: item, context: .dated) {
                            presentedSearchSheet = .detail(item)
                        }
                        if item.id != filteredResults.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .memdoCard()
            }

            Button {
                showSummary = true
            } label: {
                Label("AI에게 이 일정들 요약 요청", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(item: $presentedSearchSheet) { sheet in
            switch sheet {
            case .detail(let item):
                ScheduleDetailSheet(schedule: item, onSave: scheduleStore.save)
            case .filters:
                SearchFilterSheet(status: $status, period: $period)
            }
        }
        .alert("AI 요약", isPresented: $showSummary) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(filteredResults.isEmpty ? "요약할 일정이 없어요." : "관련 일정 \(filteredResults.count)개가 있어요. 가장 가까운 일정을 먼저 확인해 보세요.")
        }
        .alert("음성 검색", isPresented: $showVoiceHelp) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("마이크 권한을 허용하면 일정 제목과 메모를 음성으로 검색할 수 있어요.")
        }
    }
}

struct AssistantView: View {
    @State private var composer = ""
    @State private var messages: [(String, Bool)] = [
        ("매주 화요일 오후에 운동 일정을 만들어줘.", true),
        ("오후 7시부터 1시간으로 제안할게요. 8월부터 매주 반복할까요?", false)
    ]
    @State private var title = "운동"
    @State private var time = "매주 화요일 19:00"
    @State private var editingProposal = false
    @State private var added = false

    var body: some View {
        MemdoPage(title: "AI 도우미", subtitle: "확인 전에는 일정을 변경하지 않아요", eyebrow: "조용한 도우미", icon: "sparkles") {
            ForEach(messages.indices, id: \.self) { index in
                ChatBubble(text: messages[index].0, isUser: messages[index].1)
            }

            VStack(alignment: .leading, spacing: 16) {
                Label("반복 일정 제안", systemImage: "calendar.badge.plus")
                    .font(.headline)
                if editingProposal {
                    TextField("제목", text: $title).textFieldStyle(.roundedBorder)
                    TextField("시간", text: $time).textFieldStyle(.roundedBorder)
                } else {
                    LabeledContent("제목", value: title)
                    LabeledContent("시간", value: time)
                }
                LabeledContent("알림", value: "30분 전")
                Divider()
                HStack {
                    Button(editingProposal ? "수정 완료" : "수정") { editingProposal.toggle() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(added ? "추가됨" : "일정에 추가") { added = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(added)
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
                TextField("무엇을 도와드릴까요?", text: $composer)
                    .onSubmit(sendMessage)
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("보내기")
            }
            .padding(8)
            .background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(MemdoTheme.outline))
        }
        .sensoryFeedback(.success, trigger: added)
    }

    private func sendMessage() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append((text, true))
        messages.append(("좋아요. 변경 전 확인할 수 있도록 일정 제안으로 준비했어요.", false))
        composer = ""
    }
}

struct DailySummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reviews = ["디자인 시안 확인", "30분 산책"]

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

            MemdoSectionHeader(title: "결정이 필요한 일정", trailing: "\(reviews.count)개")
            if reviews.isEmpty {
                ContentUnavailableView("정리가 끝났어요", systemImage: "checkmark.circle.fill")
            } else {
                VStack(spacing: 0) {
                    ForEach(reviews, id: \.self) { title in
                        ReviewRow(
                            title: title,
                            time: title == "디자인 시안 확인" ? "14:30" : "19:00",
                            resolve: { reviews.removeAll { $0 == title } }
                        )
                        if title != reviews.last {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .memdoCard()
            }

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

            Button("정리 완료") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }
}

struct SettingsView: View {
    @State private var dailySummary = true
    @State private var calendarSync = true
    @State private var notifications = true
    @State private var summaryTime = Calendar.current.date(from: DateComponents(hour: 21, minute: 30)) ?? .now
    @State private var promptTime = Calendar.current.date(from: DateComponents(hour: 9)) ?? .now
    @State private var newsTopics: Set<String> = ["AI", "생산성"]
    @State private var showAIConsent = false

    var body: some View {
        MemdoPage(title: "설정", subtitle: "Memdo를 나에게 맞게 조정하세요", eyebrow: "나만의 Memdo", icon: "slider.horizontal.3") {
            SettingsGroup(title: "하루") {
                Toggle("오늘 요약 받기", isOn: $dailySummary)
                Divider()
                DatePicker("요약 시간", selection: $summaryTime, displayedComponents: .hourAndMinute)
                    .disabled(!dailySummary)
                Divider()
                DatePicker("계획이 없을 때", selection: $promptTime, displayedComponents: .hourAndMinute)
            }

            SettingsGroup(title: "연결 및 권한") {
                Toggle("Google Calendar", isOn: $calendarSync)
                Divider()
                Button { showAIConsent = true } label: {
                    LabeledContent("AI 데이터 접근", value: "일정 제목·시간")
                }
                .buttonStyle(.plain)
                Divider()
                Toggle("알림", isOn: $notifications)
            }

            SettingsGroup(title: "관심 뉴스") {
                HStack {
                    ForEach(["AI", "생산성", "로컬"], id: \.self) { topic in
                        Button {
                            if newsTopics.contains(topic) {
                                newsTopics.remove(topic)
                            } else {
                                newsTopics.insert(topic)
                            }
                        } label: {
                            FilterPill(title: topic, selected: newsTopics.contains(topic))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .alert("AI 데이터 접근", isPresented: $showAIConsent) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("AI는 일정 제목과 시간만 분석하며, 일정 변경은 항상 사용자의 확인 후 실행합니다.")
        }
        .sensoryFeedback(.selection, trigger: newsTopics)
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
        .padding(.bottom, 24)
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

private struct SelectedCalendarDay: Identifiable {
    let day: Int
    var id: Int { day }
}

private struct DayAgendaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    let day: Int
    @State private var selectedSchedule: ScheduleDetail?
    @State private var showAddTask = false

    private var daySchedules: [ScheduleDetail] {
        scheduleStore.items(for: day)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day == 31 ? "오늘" : day < 31 ? "지난 일정" : "예정")
                        .font(.caption.bold())
                        .foregroundStyle(MemdoTheme.accent)
                    Text("7월 \(day)일")
                        .font(.title2.bold())
                    Text(daySchedules.isEmpty ? "아직 등록된 일정이 없어요." : "\(daySchedules.count)개의 일정을 확인해 보세요.")
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if daySchedules.isEmpty {
                    ContentUnavailableView(
                        "비어 있는 하루예요",
                        systemImage: "calendar.badge.plus",
                        description: Text("편한 시간에 첫 일정을 추가해 보세요.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(daySchedules) { schedule in
                                ScheduleRow(schedule: schedule, context: .timeline) {
                                    selectedSchedule = schedule
                                }
                                if schedule.id != daySchedules.last?.id {
                                    Divider().padding(.leading, 72)
                                }
                            }
                        }
                        .background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }

                Button {
                    showAddTask = true
                } label: {
                    Label("7월 \(day)일에 새 일정", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .background(MemdoPageBackground())
            .navigationTitle("하루 일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedSchedule) { schedule in
            ScheduleDetailSheet(schedule: schedule, onSave: scheduleStore.save)
        }
        .sheet(isPresented: $showAddTask) {
            AddScheduleSheet(day: day, onSave: scheduleStore.save)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private enum SearchSheet: Identifiable {
    case detail(ScheduleDetail)
    case filters

    var id: String {
        switch self {
        case .detail(let item): "detail-\(item.id)"
        case .filters: "filters"
        }
    }
}

private struct SearchFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var status: String
    @Binding var period: String

    var body: some View {
        NavigationStack {
            Form {
                Picker("상태", selection: $status) {
                    ForEach(["전체 상태", "예정", "완료"], id: \.self) { Text($0) }
                }
                Picker("기간", selection: $period) {
                    ForEach(["전체 기간", "최근 2주", "이번 주"], id: \.self) { Text($0) }
                }
                Button("필터 초기화") {
                    status = "전체 상태"
                    period = "전체 기간"
                }
            }
            .navigationTitle("상세 필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
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
    let resolve: () -> Void

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
                Button("완료", action: resolve)
                Button("내일로", action: resolve)
                Spacer()
                Button(role: .destructive, action: resolve) {
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
                .memdoCard()
        }
    }
}
