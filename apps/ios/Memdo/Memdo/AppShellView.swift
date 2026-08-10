import SwiftUI

enum AppTab: String, CaseIterable {
    case today
    case calendar
    case settings
    case agent

    var title: String {
        switch self {
        case .today: "오늘"
        case .calendar: "캘린더"
        case .settings: "설정"
        case .agent: "Agent"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .settings: "slider.horizontal.3"
        case .agent: "sparkles"
        }
    }
}

struct AppShellView: View {
    let scheduleStore: ScheduleStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.today
    @State private var showIntentCapture = false
    @State private var intentText: String?
    @State private var lastContentTab = AppTab.today
    @State private var showCalendarSearch = false
    @State private var calendarTargetDate: Date?
    @State private var presentedSheet: AppSheetDestination?
    @State private var agentComposer = ""
    @State private var agentResponse = ""
    @State private var coachMarkTour: CoachMarkTour?
    @State private var coachMarkIndex = 0
    @State private var agentTabFrame = CGRect.zero
    @State private var scheduleSheet: ScheduleDetail?
    @AppStorage("has-seen-guide") private var hasSeenGuide = false

    var body: some View {
        appTabs
            .coachMarkOverlay(
                step: coachMarkStep,
                index: coachMarkIndex,
                count: coachMarkTour?.steps.count ?? 0,
                onPrevious: previousCoachMark,
                onNext: nextCoachMark,
                onSkip: finishCoachMarks
            )
            .modifier(
                AppShellBehavior(
                    presentedSheet: $presentedSheet,
                    agentComposer: $agentComposer,
                    agentResponse: $agentResponse,
                    onStartCoachMarkTour: startCoachMarks
                )
            )
            .environment(scheduleStore)
            .task { await scheduleStore.load() }
            .task {
                guard !hasSeenGuide else { return }
                // Let the launch-brand crossfade settle before presenting.
                try? await Task.sleep(for: .milliseconds(600))
                hasSeenGuide = true
                presentedSheet = .guide
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await scheduleStore.refresh() }
                }
            }
            .modifier(IntentCaptureBehavior { text in
                intentText = text
                showIntentCapture = true
            })
            .sheet(isPresented: $showIntentCapture) {
                EventCaptureSheet(initialText: intentText ?? "") { event in createFromCapture(event) }
            }
            .overlay { backendStateOverlay }
            .overlay(alignment: .bottom) { writeErrorToast }
    }

    @ViewBuilder
    private var writeErrorToast: some View {
        if let message = scheduleStore.lastWriteError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                )
                .padding(.horizontal, MemdoMetrics.pagePadding)
                .padding(.bottom, 12)
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { scheduleStore.dismissWriteError() }
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(4))
                    if scheduleStore.lastWriteError == message {
                        scheduleStore.dismissWriteError()
                    }
                }
        }
    }

    @ViewBuilder
    private var backendStateOverlay: some View {
        // Only the schedule-driven tabs depend on scheduleStore; Settings and Agent
        // stay reachable even while a load is stuck, so signing out (or anything
        // else in Settings) is never blocked by a backend hiccup on Today/Calendar.
        switch (scheduleStore.state, selectedTab) {
        case (_, .settings), (_, .agent):
            EmptyView()
        case (.idle, _), (.loaded, _):
            EmptyView()
        case (.loading, _):
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                ProgressView("일정을 불러오는 중")
            }
        case (.failed(let message), _):
            ZStack {
                MemdoPageBackground().ignoresSafeArea()
                ContentUnavailableView {
                    Label("백엔드에 연결할 수 없어요", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도") { Task { await scheduleStore.load() } }
                        .buttonStyle(.borderedProminent)
                    Button("설정으로 이동") { selectedTab = .settings }
                        .buttonStyle(.bordered)
                }
                .padding(MemdoMetrics.pagePadding)
            }
        }
    }

    private var appTabs: some View {
        TabView(selection: tabSelection) {
            TodayView(
                coachMarkTarget: coachMarkStep?.target,
                onOpenGuide: { presentedSheet = .guide }
            )
                .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.icon) }
                .tag(AppTab.today)
            CalendarView(
                coachMarkTarget: coachMarkStep?.target,
                isSearchPresented: $showCalendarSearch,
                targetDate: $calendarTargetDate
            )
                .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.icon) }
                .tag(AppTab.calendar)
            SettingsView(coachMarkTarget: coachMarkStep?.target)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(AppTab.settings)
            Color.clear
                .tabItem { Label(AppTab.agent.title, systemImage: AppTab.agent.icon) }
                .tag(AppTab.agent)
        }
        .overlay {
            AgentTabBridge(targetFrame: $agentTabFrame, onTap: openAgent)
                .allowsHitTesting(false)
        }
        .overlay {
            if !agentTabFrame.isEmpty {
                // coachMarkTarget must come before position: position wraps the
                // view in a container that fills the proposal, so anchoring after
                // it would register the whole screen instead of the tab slice.
                Color.clear
                    .frame(width: agentTabFrame.width, height: agentTabFrame.height)
                    .coachMarkTarget(.agentTab)
                    .position(x: agentTabFrame.midX, y: agentTabFrame.midY)
                    .allowsHitTesting(false)
            }
        }
        .modifier(NativeTabBarBehavior())
        .tint(MemdoTheme.accent)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onOpenURL(perform: openDeepLink)
        .sheet(item: $scheduleSheet) { schedule in
            ScheduleDetailSheet(schedule: schedule) { scheduleStore.save($0) }
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .agent {
                    openAgent()
                } else {
                    selectedTab = newTab
                    lastContentTab = newTab
                }
            }
        )
    }

    private func openDeepLink(_ url: URL) {
        guard url.host != "auth" else { return }
        switch url.host {
        case "calendar":
            calendarTargetDate = url.memdoDateQuery
            select(.calendar)
        case "search":
            select(.calendar)
            showCalendarSearch = true
        case "assistant": openAgent()
        case "settings": select(.settings)
        case "summary": presentedSheet = .summary
        case "complete":
            // memdo://complete/{uuid} — "완료" action from notification banner
            if let idString = url.pathComponents.dropFirst().first,
               let id = UUID(uuidString: idString),
               let schedule = scheduleStore.schedules.first(where: { $0.id == id }),
               !schedule.isDone {
                var completed = schedule
                completed.isDone = true
                scheduleStore.save(completed)
            }
        case "schedule":
            // memdo://schedule/{uuid} — tap on a per-schedule reminder
            if let idString = url.pathComponents.dropFirst().first,
               let id = UUID(uuidString: idString),
               let schedule = scheduleStore.schedules.first(where: { $0.id == id }) {
                select(.today)
                scheduleSheet = schedule
            } else {
                select(.today)
            }
        default: select(.today)
        }
    }

    private func openAgent() {
        presentedSheet = .agent(lastContentTab.agentContext)
    }

    // Creates a schedule from an App Intent-driven capture. Uses the first
    // calendar; a missing start time falls back to a task so the entry is valid.
    // A cold launch can race scheduleStore.load(), so wait briefly for calendars
    // to appear rather than dropping the capture the user just made.
    private func createFromCapture(_ event: EventDraft) {
        Task {
            var attempts = 0
            while scheduleStore.calendars.isEmpty && attempts < 20 {
                try? await Task.sleep(for: .milliseconds(100))
                attempts += 1
            }
            guard let calendar = scheduleStore.calendars.first else { return }
            var schedule = ScheduleDetail(
                scheduledDate: event.startAt ?? .now,
                startAt: event.startAt,
                endAt: event.endAt,
                title: event.title.isEmpty ? "새 일정" : event.title,
                kind: event.startAt != nil ? .event : .task,
                calendar: calendar,
                timeBucket: event.startAt.map(ScheduleTimeBucket.inferred(from:)) ?? .anytime
            )
            schedule.memo = event.notes
            if let url = event.meetingURL { schedule.meetingURLString = url.absoluteString }
            scheduleStore.save(schedule)
        }
    }

    private func select(_ tab: AppTab) {
        selectedTab = tab
        lastContentTab = tab
    }

    private var coachMarkStep: CoachMarkStep? {
        guard let steps = coachMarkTour?.steps, steps.indices.contains(coachMarkIndex) else { return nil }
        return steps[coachMarkIndex]
    }

    private func startCoachMarks(_ tour: CoachMarkTour) {
        coachMarkTour = tour
        coachMarkIndex = 0
        select(tour.steps[0].tab)
    }

    private func previousCoachMark(from displayedIndex: Int) {
        guard displayedIndex == coachMarkIndex,
              let tour = coachMarkTour,
              coachMarkIndex > 0
        else { return }
        coachMarkIndex -= 1
        select(tour.steps[coachMarkIndex].tab)
    }

    private func nextCoachMark(from displayedIndex: Int) {
        guard displayedIndex == coachMarkIndex, let tour = coachMarkTour else { return }
        let next = coachMarkIndex + 1
        guard tour.steps.indices.contains(next) else {
            finishCoachMarks()
            return
        }
        coachMarkIndex = next
        select(tour.steps[next].tab)
    }

    private func finishCoachMarks() {
        coachMarkTour = nil
        coachMarkIndex = 0
    }
}

private extension URL {
    var memdoDateQuery: Date? {
        guard let value = URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "date" })?
            .value
        else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

private enum AppSheetDestination: Identifiable {
    case agent(String)
    case guide
    case summary

    var id: String {
        switch self {
        case .agent: "agent"
        case .guide: "guide"
        case .summary: "summary"
        }
    }
}

private struct AppShellBehavior: ViewModifier {
    @Binding var presentedSheet: AppSheetDestination?
    @Binding var agentComposer: String
    @Binding var agentResponse: String
    let onStartCoachMarkTour: (CoachMarkTour) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $presentedSheet) { destination in
            switch destination {
            case .agent(let context):
                AgentSheet(
                    composer: $agentComposer,
                    response: $agentResponse,
                    context: context
                )
            case .guide:
                MemdoGuideSheet(onStartCoachMarkTour: onStartCoachMarkTour)
            case .summary:
                DailySummaryView()
            }
        }
    }
}

private extension AppTab {
    var agentContext: String {
        switch self {
        case .today: "오늘"
        case .calendar: "캘린더"
        case .settings: "설정"
        case .agent: "오늘"
        }
    }
}

/// Routes the CaptureEventIntent into the quick-add sheet. Gated because
/// `onAppIntentExecution` is iOS 26+; older systems simply don't wire it.
private struct IntentCaptureBehavior: ViewModifier {
    let onFire: (String?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.onAppIntentExecution(CaptureEventIntent.self) { intent in onFire(intent.text) }
        } else {
            content
        }
    }
}

private struct NativeTabBarBehavior: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
