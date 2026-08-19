import Observation
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
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(MemdoSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.today
    @State private var showIntentCapture = false
    @State private var intentText: String?
    @State private var lastContentTab = AppTab.today
    @State private var showCalendarSearch = false
    @State private var calendarTargetDate: Date?
    @State private var presentedSheet: AppSheetDestination?
    @State private var agentSheetRouter = AgentSheetRouter()
    @State private var agentComposer = ""
    @State private var agentMessages: [AgentMessage] = []
    @State private var coachMarkTour: CoachMarkTour?
    @State private var coachMarkIndex = 0
    @State private var showTourSkipHint = false
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
                onSkip: skipCoachMarks
            )
            .modifier(
                AppShellBehavior(
                    presentedSheet: $presentedSheet,
                    onStartCoachMarkTour: startCoachMarks
                )
            )
            .background {
                AgentSheetPresenter(
                    router: agentSheetRouter,
                    composer: $agentComposer,
                    messages: $agentMessages
                )
            }
            .environment(scheduleStore)
            .task { await scheduleStore.load() }
            .task { await workoutStore.load() }
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
            .overlay(alignment: .bottom) { tourSkipHint }
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
                    try? await Task.sleep(for: MemdoMetrics.bannerDismissDuration)
                    if scheduleStore.lastWriteError == message {
                        scheduleStore.dismissWriteError()
                    }
                }
        }
    }

    @ViewBuilder
    private var tourSkipHint: some View {
        if showTourSkipHint {
            Label("설정에서 '앱 투어 다시 보기'로 언제든 다시 볼 수 있어요.", systemImage: "info.circle")
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
                .task {
                    try? await Task.sleep(for: MemdoMetrics.bannerDismissDuration)
                    withAnimation(reduceMotion ? nil : .easeOut) { showTourSkipHint = false }
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
            SettingsView(coachMarkTarget: coachMarkStep?.target, onStartCoachMarkTour: startCoachMarks)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(AppTab.settings)
            Color.clear
                .tabItem { Label(AppTab.agent.title, systemImage: AppTab.agent.icon) }
                .tag(AppTab.agent)
        }
        .overlay {
            AgentTabBridge(targetFrame: $agentTabFrame, onTap: openAgent)
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
        agentSheetRouter.present(
            lastContentTab.agentContext,
            requiresLogin: session.phase == .guest
        )
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

    private func skipCoachMarks() {
        finishCoachMarks()
        withAnimation(reduceMotion ? nil : .easeIn) { showTourSkipHint = true }
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
    case guide
    case summary

    var id: String {
        switch self {
        case .guide: "guide"
        case .summary: "summary"
        }
    }
}

private struct AppShellBehavior: ViewModifier {
    @Binding var presentedSheet: AppSheetDestination?
    let onStartCoachMarkTour: (CoachMarkTour) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $presentedSheet) { destination in
            switch destination {
            case .guide:
                MemdoGuideSheet(onStartCoachMarkTour: onStartCoachMarkTour)
            case .summary:
                DailySummaryView()
            }
        }
    }
}

@MainActor
@Observable
private final class AgentSheetRouter {
    var destination: AgentSheetDestination?

    func present(_ context: AgentContext, requiresLogin: Bool) {
        destination = requiresLogin ? .guestLoginGate : .agent(context)
    }
}

private enum AgentSheetDestination: Identifiable {
    case agent(AgentContext)
    case guestLoginGate

    var id: String {
        switch self {
        case .agent: "agent"
        case .guestLoginGate: "guestLoginGate"
        }
    }
}

private struct AgentSheetPresenter: View {
    @Bindable var router: AgentSheetRouter
    @Binding var composer: String
    @Binding var messages: [AgentMessage]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $router.destination) { destination in
                switch destination {
                case .agent(let context):
                    AgentSheet(
                        composer: $composer,
                        messages: $messages,
                        context: context
                    )
                case .guestLoginGate:
                    GuestLoginGateSheet()
                }
            }
    }
}

private extension AppTab {
    var agentContext: AgentContext {
        switch self {
        case .today: .today
        case .calendar: .calendar
        case .settings: .settings
        case .agent: .today
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

private struct GuestLoginGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MemdoSession.self) private var session

    var body: some View {
        NavigationStack {
            MemdoSignInView(
                session: session,
                gateTitle: "로그인하고 Agent 사용하기",
                gateSubtitle: "로그인하면 지금까지 만든 일정이 그대로 유지되고\nAgent를 제한 없이 사용할 수 있어요."
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("나중에") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
    }
}
