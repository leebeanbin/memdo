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
    @State private var selectedTab = AppTab.today
    @State private var lastContentTab = AppTab.today
    @State private var showCalendarSearch = false
    @State private var presentedSheet: AppSheetDestination?
    @State private var agentComposer = ""
    @State private var agentResponse = ""

    var body: some View {
        appTabs
            .modifier(
                AppShellBehavior(
                    presentedSheet: $presentedSheet,
                    agentComposer: $agentComposer,
                    agentResponse: $agentResponse
                )
            )
            .environment(scheduleStore)
            .task { await scheduleStore.load() }
            .overlay { backendStateOverlay }
    }

    @ViewBuilder
    private var backendStateOverlay: some View {
        switch scheduleStore.state {
        case .idle, .loaded:
            EmptyView()
        case .loading:
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                ProgressView("일정을 불러오는 중")
            }
        case .failed(let message):
            ZStack {
                MemdoPageBackground().ignoresSafeArea()
                ContentUnavailableView {
                    Label("백엔드에 연결할 수 없어요", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도") { Task { await scheduleStore.load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(MemdoMetrics.pagePadding)
            }
        }
    }

    private var appTabs: some View {
        TabView(selection: tabSelection) {
            TodayView()
                .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.icon) }
                .tag(AppTab.today)
            CalendarView(isSearchPresented: $showCalendarSearch)
                .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.icon) }
                .tag(AppTab.calendar)
            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(AppTab.settings)
            Color.clear
                .tabItem { Label(AppTab.agent.title, systemImage: AppTab.agent.icon) }
                .tag(AppTab.agent)
        }
        .modifier(NativeTabBarBehavior())
        .tint(MemdoTheme.accent)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onOpenURL(perform: openDeepLink)
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
        case "calendar": select(.calendar)
        case "search":
            select(.calendar)
            showCalendarSearch = true
        case "assistant": openAgent()
        case "settings": select(.settings)
        case "summary": presentedSheet = .summary
        default: select(.today)
        }
    }

    private func openAgent() {
        presentedSheet = .agent(lastContentTab.agentContext)
    }

    private func select(_ tab: AppTab) {
        selectedTab = tab
        lastContentTab = tab
    }
}

private enum AppSheetDestination: Identifiable {
    case agent(String)
    case summary

    var id: String {
        switch self {
        case .agent: "agent"
        case .summary: "summary"
        }
    }
}

private struct AppShellBehavior: ViewModifier {
    @Binding var presentedSheet: AppSheetDestination?
    @Binding var agentComposer: String
    @Binding var agentResponse: String

    func body(content: Content) -> some View {
        content.sheet(item: $presentedSheet) { destination in
            switch destination {
            case .agent(let context):
                AgentSheet(
                    composer: $agentComposer,
                    response: $agentResponse,
                    context: context
                )
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
