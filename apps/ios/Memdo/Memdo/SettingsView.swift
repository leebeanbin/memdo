import AuthenticationServices
import SwiftUI

private enum SettingsDefaults {
    static let summaryHour = 21
    static let summaryMinute = 30
    static let promptHour = 9
    static let preferencePushDebounce: Duration = .milliseconds(500)
}

struct SettingsView: View {
    let coachMarkTarget: CoachMarkTarget?
    let onStartCoachMarkTour: ((CoachMarkTour) -> Void)?
    @Environment(MemdoSession.self) private var session
    @State private var dailySummary = true
    @State private var planningPromptEnabled = true
    @State private var notifications = true
    @State private var summaryTime = Calendar.current.date(from: DateComponents(hour: SettingsDefaults.summaryHour, minute: SettingsDefaults.summaryMinute)) ?? .now
    @State private var promptTime = Calendar.current.date(from: DateComponents(hour: SettingsDefaults.promptHour)) ?? .now
    @State private var presentedSheet: SettingsSheet?
    @State private var showsWallpaperPreview = false
    @State private var showsSignOutConfirmation = false
    @State private var summaryTimePushTask: Task<Void, Never>?
    @State private var promptTimePushTask: Task<Void, Never>?
    @AppStorage(
        MemdoWidgetStorage.hideContentKey,
        store: UserDefaults(suiteName: MemdoWidgetStorage.suiteName)
    ) private var hideWidgetContent = false

    init(coachMarkTarget: CoachMarkTarget? = nil, onStartCoachMarkTour: ((CoachMarkTour) -> Void)? = nil) {
        self.coachMarkTarget = coachMarkTarget
        self.onStartCoachMarkTour = onStartCoachMarkTour
    }

    var body: some View {
        MemdoPage(
            title: "설정",
            subtitle: "",
            eyebrow: "",
            bottomClearance: coachMarkTarget == nil
                ? MemdoMetrics.tabBarClearance
                : MemdoMetrics.tabBarClearance + 280,
            scrollTarget: coachMarkTarget
        ) {
            if let error = session.preferencesStore?.lastError {
                Button {
                    session.preferencesStore?.dismissError()
                } label: {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(MemdoTypography.caption)
                        .foregroundStyle(.red)
                        .memdoSettingsRow()
                }
                .buttonStyle(.plain)
            }

            SettingsGroup(title: "하루", icon: "sun.max") {
                Button { presentedSheet = .routines } label: {
                    SettingsDisclosureRow(title: "알림 및 루틴", value: routineSummary)
                }
                .buttonStyle(.plain)
            }
            .id(CoachMarkTarget.settingsDay)
            .coachMarkTarget(.settingsDay)

            SettingsGroup(title: "위젯", icon: "rectangle.grid.2x2") {
                Button { showsWallpaperPreview = true } label: {
                    SettingsDisclosureRow(title: "전체 달력 배경화면", value: "미리보기 · 저장")
                }
                .buttonStyle(.plain)
            }
            .id(CoachMarkTarget.settingsWidget)
            .coachMarkTarget(.settingsWidget)

            SettingsGroup(title: "Agent", icon: "sparkles") {
                Button { presentedSheet = .agentSettings } label: {
                    SettingsDisclosureRow(title: "연결 및 권한", value: "관리")
                }
                .buttonStyle(.plain)
            }
            .id(CoachMarkTarget.settingsConnections)
            .coachMarkTarget(.settingsConnections)

            SettingsGroup(title: "계정", icon: "person.crop.circle") {
                if session.phase == .guest {
                    GuestUpgradeRow(onUpgrade: { presentedSheet = .guestUpgrade })
                    Divider()
                    Button { showsSignOutConfirmation = true } label: {
                        HStack {
                            Text("로그아웃")
                                .font(MemdoTypography.subtitle)
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(MemdoTypography.captionEmphasis)
                                .foregroundStyle(.red)
                                .accessibilityHidden(true)
                        }
                        .memdoSettingsRow()
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isBusy)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(MemdoTypography.title2)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.accountLabel)
                                .font(MemdoTypography.action)
                        }
                        Spacer()
                        Button { showsSignOutConfirmation = true } label: {
                            Text("로그아웃")
                                .font(MemdoTypography.captionEmphasis)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isBusy)
                    }
                    .memdoSettingsRow()
                }

                if let errorMessage = session.errorMessage {
                    Divider()
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(MemdoTypography.caption)
                        .foregroundStyle(.red)
                        .memdoSettingsRow()
                }
            }

            if let onStartCoachMarkTour {
                SettingsGroup(title: "도움말", icon: "questionmark.circle") {
                    Button {
                        onStartCoachMarkTour(.app)
                    } label: {
                        HStack {
                            Label("앱 투어 다시 보기", systemImage: "map")
                                .font(MemdoTypography.subtitle)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(MemdoTypography.captionEmphasis)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                                .accessibilityHidden(true)
                        }
                        .memdoSettingsRow()
                    }
                    .buttonStyle(.plain)
                }
            }

        }
        .confirmationDialog(
            session.phase == .guest ? "게스트 로그아웃" : "로그아웃 하시겠어요?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("로그아웃", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(session.phase == .guest
                ? "저장된 일정과 기록이 모두 삭제됩니다."
                : "이 기기에서 로그아웃합니다.")
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .agentSettings:
                AgentSettingsSheet()
            case .guestUpgrade:
                GuestUpgradeSheet()
            case .routines:
                RoutineSettingsSheet(
                    notifications: $notifications,
                    planningPromptEnabled: $planningPromptEnabled,
                    promptTime: $promptTime,
                    dailySummary: $dailySummary,
                    summaryTime: $summaryTime
                )
            }
        }
        .fullScreenCover(isPresented: $showsWallpaperPreview) {
            WallpaperPreviewSheet { showsWallpaperPreview = false }
        }
        .task { await loadPreferences() }
        .onChange(of: dailySummary) { _, value in
            guard session.preferencesStore?.preferences?.dailyReviewEnabled != value else { return }
            push {
                $0.dailyReviewEnabled = value
                if value {
                    $0.dailyReviewTime = ClockString.from(summaryTime)
                    if $0.dailyReviewDays.isEmpty { $0.dailyReviewDays = UserPreferences.allWeekdays }
                }
            }
        }
        .onChange(of: planningPromptEnabled) { _, value in
            let savedValue = session.preferencesStore?.preferences?.planningPromptTime
            guard (savedValue != nil) != value else { return }
            push { $0.planningPromptTime = value ? ClockString.from(promptTime) : nil }
        }
        .onChange(of: summaryTime) { _, value in
            guard session.preferencesStore?.preferences?.dailyReviewTime != ClockString.from(value) else { return }
            summaryTimePushTask?.cancel()
            summaryTimePushTask = Task {
                try? await Task.sleep(for: SettingsDefaults.preferencePushDebounce)
                guard !Task.isCancelled else { return }
                push { $0.dailyReviewTime = ClockString.from(value) }
            }
        }
        .onChange(of: promptTime) { _, value in
            guard planningPromptEnabled else { return }
            guard session.preferencesStore?.preferences?.planningPromptTime != ClockString.from(value) else { return }
            promptTimePushTask?.cancel()
            promptTimePushTask = Task {
                try? await Task.sleep(for: SettingsDefaults.preferencePushDebounce)
                guard !Task.isCancelled else { return }
                push { $0.planningPromptTime = ClockString.from(value) }
            }
        }
        .onChange(of: notifications) { _, value in
            guard session.preferencesStore?.preferences?.notificationsEnabled != value else { return }
            if value {
                Task { await NotificationScheduler.requestPermission() }
            } else {
                Task { await NotificationScheduler.cancelAll() }
            }
            push { $0.notificationsEnabled = value }
        }
        .task(id: session.preferencesStore?.preferences) {
            guard let prefs = session.preferencesStore?.preferences else { return }
            await NotificationScheduler.schedule(for: prefs)
        }
    }

    private func loadPreferences() async {
        guard let store = session.preferencesStore else { return }
        await store.load()
        guard let preferences = store.preferences else { return }
        dailySummary = preferences.dailyReviewEnabled
        planningPromptEnabled = preferences.planningPromptTime != nil
        notifications = preferences.notificationsEnabled
        hideWidgetContent = preferences.hideWidgetContent
        if let time = ClockString.date(preferences.dailyReviewTime) { summaryTime = time }
        if let time = ClockString.date(preferences.planningPromptTime) { promptTime = time }
    }

    private func push(_ transform: @escaping (inout UserPreferences) -> Void) {
        guard session.preferencesStore != nil else { return }
        Task { await session.preferencesStore?.update(transform) }
    }

    private var routineSummary: String {
        guard notifications else { return "꺼짐" }
        let timeStyle = Date.FormatStyle.dateTime
            .hour()
            .minute()
            .locale(Locale(identifier: "ko_KR"))
        let start = planningPromptEnabled ? "시작 \(promptTime.formatted(timeStyle))" : nil
        let review = dailySummary ? "정리 \(summaryTime.formatted(timeStyle))" : nil
        let labels = [start, review].compactMap { $0 }
        return labels.isEmpty ? "설정 안 함" : labels.joined(separator: " · ")
    }

}

private enum ConnectionIcon {
    case asset(String)
    case memdo
    case system(String)
}

private struct ConnectionMark: View {
    let icon: ConnectionIcon

    var body: some View {
        Group {
            switch icon {
            case .asset(let name):
                Image(name)
                    .resizable()
                    .scaledToFit()
            case .memdo:
                MemdoBrandMark(size: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MemdoTheme.surface)
            case .system(let name):
                Image(systemName: name)
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.brand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MemdoTheme.brandSoft)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: MemdoMetrics.iconRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct AgentConnectionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: ConnectionIcon
    let title: String
    let capability: String
    let status: String
    var badge: String?
    var showsChevron = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ConnectionMark(icon: icon)

            VStack(alignment: .leading, spacing: 4) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(title)
                        .font(MemdoTypography.action)
                    if let badge {
                        ConnectionBadge(title: badge)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(MemdoTypography.action)
                        if let badge {
                            ConnectionBadge(title: badge)
                        }
                    }
                }
                Text(capability)
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                if dynamicTypeSize.isAccessibilitySize {
                    Text(status)
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }

            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(status)
                    .font(MemdoTypography.captionEmphasis)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(MemdoTypography.captionEmphasis)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 4)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(capability), \(status)")
    }
}

private struct ConnectionBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(MemdoTypography.caption2Emphasis)
            .dynamicTypeSize(.small ... .large)
            .tracking(0.4)
            .foregroundStyle(MemdoTheme.brand)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(MemdoTheme.brandSoft, in: Capsule())
    }
}

private struct SettingsDisclosureRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if dynamicTypeSize.isAccessibilitySize {
                    Text(value)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(value)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            Image(systemName: "chevron.right")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .memdoSettingsRow()
    }
}

private struct SettingsTimePicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    @Binding var selection: Date

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                    DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DatePicker(selection: $selection, displayedComponents: .hourAndMinute) {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: "clock")
                            .foregroundStyle(MemdoTheme.secondaryInk)
                            .frame(width: 24)
                    }
                }
            }
        }
        .memdoSettingsRow()
    }
}

private enum SettingsSheet: String, Identifiable {
    case agentSettings
    case guestUpgrade
    case routines
    var id: String { rawValue }
}

private struct RoutineSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var notifications: Bool
    @Binding var planningPromptEnabled: Bool
    @Binding var promptTime: Date
    @Binding var dailySummary: Bool
    @Binding var summaryTime: Date

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $notifications) {
                        RoutineLabel(
                            icon: "bell",
                            title: "전체 알림",
                            detail: "Memdo의 모든 알림"
                        )
                    }
                    .memdoToggle()

                    Toggle(isOn: $planningPromptEnabled) {
                        RoutineLabel(
                            icon: "sun.horizon",
                            title: "하루 시작",
                            detail: "계획을 시작할 시간"
                        )
                    }
                    .memdoToggle()
                    .disabled(!notifications)
                    if planningPromptEnabled {
                        SettingsTimePicker(title: "시작 시간", selection: $promptTime)
                            .disabled(!notifications)
                    }

                    Toggle(isOn: $dailySummary) {
                        RoutineLabel(
                            icon: "moon.stars",
                            title: "하루 정리",
                            detail: "완료와 미완료 일정 확인"
                        )
                    }
                    .memdoToggle()
                    .disabled(!notifications)
                    if dailySummary {
                        SettingsTimePicker(title: "정리 시간", selection: $summaryTime)
                            .disabled(!notifications)
                    }
                } footer: {
                    Text("일정별 알림은 각 일정의 상세 화면에서 따로 설정해요.")
                }
            }
            .memdoSystemList()
            .navigationTitle("알림 및 루틴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.medium, .large])
    }
}

private struct RoutineLabel: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(width: 24)
        }
    }
}

@MainActor
private final class GoogleCalendarAuthPresentationContext: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

private enum AgentSettingsDestination: String, Identifiable {
    case aiConsent
    case cloudAgent
    case googleCalendar
    case privacy
    case slack

    var id: String { rawValue }
}

private struct AgentSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var presentedSheet: AgentSettingsDestination?
    @State private var googleCalendarConnected: Bool?
    @State private var cloudAgentConnected: Bool?
    @State private var slackConnected = false
    @State private var showsServices = false
    @State private var showsData = false

    private var serviceStatus: String {
        guard let googleCalendarConnected else { return "확인 중" }
        let count = (googleCalendarConnected ? 1 : 0) + (slackConnected ? 1 : 0)
        return "\(count)/2 연결"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { presentedSheet = .cloudAgent } label: {
                        AgentConnectionRow(
                            icon: .system("cloud"),
                            title: "모델 및 사용량",
                            capability: "OpenRouter · 모델 · 비용",
                            status: connectionStatus(cloudAgentConnected)
                        )
                    }
                    .buttonStyle(.plain)

                    DisclosureGroup(isExpanded: $showsServices) {
                        VStack(spacing: 0) {
                            Button { presentedSheet = .googleCalendar } label: {
                                AgentConnectionRow(
                                    icon: .asset("GoogleCalendar"),
                                    title: "Google Calendar",
                                    capability: "일정 읽기 전용",
                                    status: connectionStatus(googleCalendarConnected),
                                    badge: nil
                                )
                            }
                            .buttonStyle(.plain)
                            Divider()
                            Button { presentedSheet = .slack } label: {
                                AgentConnectionRow(
                                    icon: .asset("Slack"),
                                    title: "Slack",
                                    capability: "새 일정·완료 알림",
                                    status: slackConnected ? "연결됨" : "미연결",
                                    badge: nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } label: {
                        AgentConnectionRow(
                            icon: .system("link"),
                            title: "연결된 서비스",
                            capability: "Google Calendar · Slack",
                            status: serviceStatus,
                            showsChevron: false
                        )
                    }

                    DisclosureGroup(isExpanded: $showsData) {
                        VStack(spacing: 0) {
                            Button { presentedSheet = .aiConsent } label: {
                                AgentConnectionRow(
                                    icon: .memdo,
                                    title: "Agent 사용 범위",
                                    capability: "일정 제목 · 시간",
                                    status: "설정"
                                )
                            }
                            .buttonStyle(.plain)
                            Divider()
                            Button { presentedSheet = .privacy } label: {
                                AgentConnectionRow(
                                    icon: .system("hand.raised.fill"),
                                    title: "데이터 관리",
                                    capability: "보관 · 철회 · 연결 해제",
                                    status: "확인"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } label: {
                        AgentConnectionRow(
                            icon: .memdo,
                            title: "데이터 및 권한",
                            capability: "사용 범위 · 보관 · 철회",
                            status: "관리",
                            showsChevron: false
                        )
                    }
                } footer: {
                    Text("Agent는 일정을 변경하기 전에 항상 확인을 요청해요.")
                }
            }
            .memdoSystemList()
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .aiConsent:
                AIConsentSheet()
            case .cloudAgent:
                CloudAgentConnectionSheet()
            case .googleCalendar:
                GoogleCalendarConnectionSheet()
            case .privacy:
                PrivacySheet()
            case .slack:
                SlackConnectionSheet()
            }
        }
        .memdoSheetPresentation([.medium, .large])
        .task { await loadStatuses() }
        .onChange(of: presentedSheet) { _, destination in
            guard destination == nil else { return }
            Task { await loadStatuses() }
        }
    }

    private func connectionStatus(_ isConnected: Bool?) -> String {
        guard let isConnected else { return "확인 중" }
        return isConnected ? "연결됨" : "미연결"
    }

    private func loadStatuses() async {
        googleCalendarConnected = (try? await scheduleStore.googleCalendarStatus())?.connected == true
        cloudAgentConnected = (try? await scheduleStore.agentKeyConnected()) == true
        slackConnected = !SlackNotifier.webhookURL.isEmpty
    }
}

private struct GoogleCalendarConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var status: GoogleCalendarStatusResponseDTO?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var authSession: ASWebAuthenticationSession?
    private let presentationContext = GoogleCalendarAuthPresentationContext()

    private var isConnected: Bool { status?.connected == true }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MCPToolIdentityRow(
                        icon: .asset("GoogleCalendar"),
                        title: "Google Calendar",
                        summary: "Google Calendar 일정을 가져와서 내 캘린더에 함께 보여줘요."
                    )
                } header: {
                    Text("Agent MCP 도구")
                }
                Section("연결하면 가능한 일") {
                    Label("Google Calendar 일정을 캘린더 화면에 함께 표시", systemImage: "calendar")
                    Label("15분마다 자동으로 최신 일정 반영", systemImage: "arrow.triangle.2.circlepath")
                }
                Section("권한 원칙") {
                    Label("읽기 전용 — Google Calendar에 쓰거나 수정하지 않음", systemImage: "eye")
                }
                if isConnected {
                    Section {
                        if let lastSyncedAt = status?.lastSyncedAt {
                            LabeledContent("마지막 동기화", value: lastSyncedAt)
                        }
                        Button(role: .destructive, action: disconnect) {
                            if isBusy {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("연결 해제 중")
                                }
                            } else {
                                Text("연결 해지")
                            }
                        }
                            .disabled(isBusy)
                    }
                } else {
                    Section {
                        Button(action: connect) {
                            if isBusy {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("연결 중")
                                }
                            } else {
                                Text("Google Calendar 연결")
                            }
                        }
                            .disabled(isBusy)
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .memdoSystemList()
            .navigationTitle("Google Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
        .task { await loadStatus() }
    }

    private func loadStatus() async {
        do {
            status = try await scheduleStore.googleCalendarStatus()
        } catch {
            // Silent: an unknown connection state just shows the "연결" button,
            // which re-checks on the next action anyway.
        }
    }

    private func connect() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                let authorizationURL = try await scheduleStore.googleCalendarStart()
                let callbackURL = try await withCheckedThrowingContinuation { (
                    continuation: CheckedContinuation<URL, Error>
                ) in
                    let session = ASWebAuthenticationSession(
                        url: authorizationURL,
                        callbackURLScheme: "memdo"
                    ) { url, error in
                        if let url {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(
                                throwing: error ?? ScheduleAPIError.invalidResponse
                            )
                        }
                    }
                    session.presentationContextProvider = presentationContext
                    session.prefersEphemeralWebBrowserSession = true
                    authSession = session
                    session.start()
                }
                let statusValue = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "status" })?.value
                if statusValue != "success" {
                    errorMessage = "연결이 취소되었어요."
                    return
                }
                await loadStatus()
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                errorMessage = "연결하지 못했어요. 잠시 후 다시 시도해 주세요."
            }
        }
    }

    private func disconnect() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await scheduleStore.googleCalendarDisconnect()
                await loadStatus()
            } catch {
                errorMessage = "연결 해지에 실패했어요. 잠시 후 다시 시도해 주세요."
            }
        }
    }
}

private struct SlackConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    // Keychain-backed (see SlackNotifier) rather than @AppStorage -- a Slack
    // Incoming Webhook URL is a bearer credential, not a plain preference.
    @State private var webhookURL = ""
    @State private var draftURL = ""
    @State private var isTesting = false
    @State private var testResult: SlackTestResult?
    @State private var showDisconnectConfirm = false

    private var isConnected: Bool { !webhookURL.isEmpty }
    private var maskedURL: String {
        guard let host = URL(string: webhookURL)?.host else { return webhookURL }
        return "hooks.slack.com/…/\(String(webhookURL.suffix(8)))"
            .replacingOccurrences(of: host, with: "hooks.slack.com")
    }
    private var canConnect: Bool {
        draftURL.hasPrefix("https://hooks.slack.com/services/")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MCPToolIdentityRow(
                        icon: .asset("Slack"),
                        title: "Slack",
                        summary: "선택한 채널로 일정 알림을 보내요."
                    )
                } header: {
                    Text("Slack 알림")
                }
                Section("연결하면 가능한 일") {
                    Label("새 일정 만들면 채널에 알림", systemImage: "calendar.badge.plus")
                    Label("할 일 완료하면 채널에 알림", systemImage: "checkmark.circle")
                    Label("테스트 메시지로 연결 확인", systemImage: "paperplane")
                }
                Section("자동으로 하지 않는 일") {
                    Label("채널 기록·DM을 읽지 않음", systemImage: "lock")
                    Label("전송 전 채널과 내용을 확인", systemImage: "checkmark.shield")
                    Label("개인 일정은 기본 공유 안 함", systemImage: "person.crop.circle.badge.xmark")
                }

                if isConnected {
                    Section("연결된 채널") {
                        LabeledContent("Webhook URL") {
                            Text(maskedURL)
                                .font(MemdoTypography.caption.monospacedDigit())
                                .foregroundStyle(MemdoTheme.secondaryInk)
                                .lineLimit(1)
                        }
                        Button {
                            Task { await sendTestMessage() }
                        } label: {
                            if isTesting {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("전송 중")
                                }
                            } else {
                                Text("테스트 메시지 보내기")
                            }
                        }
                        .disabled(isTesting)
                    }
                    if let result = testResult {
                        Section {
                            Label(result.message, systemImage: result.icon)
                                .foregroundStyle(result.isSuccess ? .green : .red)
                                .font(MemdoTypography.caption)
                        }
                    }
                    Section {
                        Button("연결 해제", role: .destructive) {
                            showDisconnectConfirm = true
                        }
                    }
                } else {
                    Section {
                        TextField("https://hooks.slack.com/services/…", text: $draftURL)
                            .font(MemdoTypography.caption.monospacedDigit())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("연결") {
                            webhookURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            SlackNotifier.webhookURL = webhookURL
                            draftURL = ""
                        }
                        .disabled(!canConnect)
                    } header: {
                        Text("Incoming Webhook URL")
                    } footer: {
                        Text("Slack 워크스페이스 설정 → 앱 → Incoming Webhooks에서 URL을 발급받아 붙여넣으세요.")
                    }
                }
            }
            .memdoSystemList()
            .navigationTitle("Slack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .confirmationDialog("Slack 연결을 해제할까요?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("연결 해제", role: .destructive) {
                webhookURL = ""
                SlackNotifier.webhookURL = ""
                testResult = nil
            }
            Button("취소", role: .cancel) {}
        }
        .memdoSheetPresentation([.large])
        .task { webhookURL = SlackNotifier.webhookURL }
    }

    private func sendTestMessage() async {
        guard let url = URL(string: webhookURL) else { return }
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            let payload = ["text": "✅ Memdo에서 보낸 테스트 메시지예요. 연결이 잘 됐어요!"]
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            testResult = ok
                ? SlackTestResult(isSuccess: true, message: "Slack 채널에 메시지를 전달했어요.", icon: "checkmark.circle.fill")
                : SlackTestResult(isSuccess: false, message: "전송에 실패했어요. URL을 확인해 주세요.", icon: "exclamationmark.circle.fill")
        } catch {
            testResult = SlackTestResult(isSuccess: false, message: "네트워크 오류: \(error.localizedDescription)", icon: "wifi.exclamationmark")
        }
    }
}

private struct SlackTestResult {
    let isSuccess: Bool
    let message: String
    let icon: String
}

/// Not private -- AssistantView presents this directly when the cloud Agent
/// path is needed but no OpenRouter key is connected yet, instead of only
/// erroring after a wasted round trip and pointing the user back to Settings.
struct CloudAgentConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var isConnected: Bool?
    @State private var draftKey = ""
    @State private var isBusy = false
    @State private var isLoadingDetails = false
    @State private var errorMessage: String?
    @State private var detailErrorMessage: String?
    @State private var showDisconnectConfirm = false
    @State private var models: [AgentModelDTO] = []
    @State private var usage: AgentUsageResponseDTO?
    @State private var selectedModel = CloudAgentModelPreference.selected
        ?? CloudAgentModelPreference.defaultID
    @AppStorage("memdo.v1.agentShowsActualCost") private var showsActualCost = false

    private var canConnect: Bool {
        draftKey.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
    }

    var body: some View {
        NavigationStack {
            Group {
                if isConnected == false {
                    disconnectedContent
                } else if isConnected == nil {
                    ProgressView("연결 상태 확인 중")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                    Section {
                        LabeledContent("상태", value: connectionStatus)
                    } header: {
                        Label("OpenRouter", systemImage: "cloud")
                    }
                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.circle")
                                .font(MemdoTypography.caption)
                                .foregroundStyle(MemdoTheme.destructive)
                        }
                    }

                    Section {
                        if models.isEmpty {
                            loadingRow(isLoadingDetails ? "모델을 불러오는 중" : "모델을 불러오지 못했어요")
                        } else {
                            ForEach(models) { model in
                                modelRow(model)
                            }
                        }
                    } header: {
                        Text("모델")
                    } footer: {
                        Text("가격은 OpenRouter의 현재 1M 토큰당 요금이에요.")
                    }

                    Section("최근 30일") {
                        Toggle("실제 비용 표시", isOn: $showsActualCost)
                            .memdoToggle()
                        if let usage {
                            LabeledContent("요청", value: "\(usage.totalRequests)회")
                            if showsActualCost {
                                LabeledContent("비용", value: usageCost(usage.totalCostUsd))
                                    .monospacedDigit()
                            }
                            ForEach(usage.recent) { item in
                                usageRow(item)
                            }
                        } else {
                            loadingRow(isLoadingDetails ? "사용량을 불러오는 중" : "사용량을 불러오지 못했어요")
                        }
                    }

                    if let detailErrorMessage {
                        Section {
                            Label(detailErrorMessage, systemImage: "exclamationmark.circle")
                                .font(MemdoTypography.caption)
                                .foregroundStyle(MemdoTheme.destructive)
                            Button("다시 시도") {
                                Task { await loadConnectedContent() }
                            }
                            .buttonStyle(MemdoSecondaryActionButtonStyle())
                            .disabled(isLoadingDetails)
                        }
                    }
                    }
                    .memdoSystemList()
                }
            }
            .background(MemdoTheme.background)
            .navigationTitle("클라우드 모델")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isConnected == true {
                        Button {
                            showDisconnectConfirm = true
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("연결 관리")
                        .disabled(isBusy)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .confirmationDialog(
            "OpenRouter 연결을 해제할까요?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("연결 해제", role: .destructive) { Task { await disconnect() } }
            Button("취소", role: .cancel) {}
        }
        .memdoSheetPresentation([.height(350), .large])
        .task { await loadStatus() }
    }

    private var disconnectedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "cloud")
                        .font(.body.weight(.medium))
                        .frame(width: 36, height: 36)
                        .background(MemdoTheme.accentSoft, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenRouter")
                            .font(MemdoTypography.sectionTitle)
                        Text("내 API 키로 클라우드 모델 사용")
                            .font(MemdoTypography.caption)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Text("미연결")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API 키")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                    HStack(spacing: 8) {
                        SecureField("sk-or-v1-…", text: $draftKey)
                            .font(MemdoTypography.subtitle.monospacedDigit())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
                            .background(
                                MemdoTheme.surface,
                                in: RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
                                    .stroke(MemdoTheme.controlOutline, lineWidth: 0.5)
                            }
                        pasteButton
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(MemdoTypography.caption)
                            .foregroundStyle(MemdoTheme.destructive)
                    }
                }

                connectButton

                Label("키는 암호화해 저장하며 앱에 다시 표시하지 않아요.", systemImage: "lock")
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .padding(MemdoMetrics.pagePadding)
        }
    }

    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { values in
            draftKey = values.first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.roundedRectangle)
        .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
        .accessibilityLabel("API 키 붙여넣기")
    }

    private var connectButton: some View {
        Button {
            Task { await connect() }
        } label: {
            if isBusy {
                ProgressView()
            } else {
                Text("OpenRouter 연결")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle)
        .tint(MemdoTheme.accent)
        .foregroundStyle(MemdoTheme.onAccent)
        .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
        .disabled(!canConnect || isBusy)
    }

    private var connectionStatus: String {
        guard let isConnected else { return "확인 중" }
        return isConnected ? "연결됨" : "미연결"
    }

    @ViewBuilder
    private func loadingRow(_ title: String) -> some View {
        if isLoadingDetails {
            ProgressView(title)
                .frame(minHeight: MemdoMetrics.touchTarget)
        } else {
            Label(title, systemImage: "exclamationmark.circle")
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(minHeight: MemdoMetrics.touchTarget)
        }
    }

    private func modelRow(_ model: AgentModelDTO) -> some View {
        Button {
            selectedModel = model.id
            CloudAgentModelPreference.selected = model.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedModel == model.id ? "checkmark.circle.fill" : "circle")
                    .font(MemdoTypography.title3)
                    .foregroundStyle(selectedModel == model.id ? MemdoTheme.brand : MemdoTheme.secondaryInk)
                    .frame(width: 24, height: MemdoMetrics.touchTarget)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(MemdoTypography.action)
                        .foregroundStyle(MemdoTheme.ink)
                        .lineLimit(1)
                    Text(modelPrice(model))
                        .font(MemdoTypography.caption2.monospacedDigit())
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.name), \(modelPrice(model))")
        .accessibilityAddTraits(selectedModel == model.id ? .isSelected : [])
    }

    private func usageRow(_ item: AgentUsageItemDTO) -> some View {
        HStack(spacing: MemdoMetrics.rowSpacing) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(width: 24, height: MemdoMetrics.touchTarget)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(models.first(where: { $0.id == item.model })?.name ?? item.model)
                    .font(MemdoTypography.subtitle)
                    .lineLimit(1)
                Text(usageDate(item.createdAt))
                    .font(MemdoTypography.caption2)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            Spacer(minLength: 8)
            if showsActualCost {
                Text(usageCost(item.costUsd))
                    .font(MemdoTypography.caption2.monospacedDigit())
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
        .frame(minHeight: 52)
    }

    private func loadStatus() async {
        do {
            isConnected = try await scheduleStore.agentKeyConnected()
            if isConnected == true { await loadConnectedContent() }
        } catch {
            isConnected = false
            errorMessage = "연결 상태를 확인하지 못했어요."
        }
    }

    private func connect() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await scheduleStore.saveAgentKey(draftKey.trimmingCharacters(in: .whitespacesAndNewlines))
            draftKey = ""
            isConnected = true
            await loadConnectedContent()
        } catch {
            errorMessage = "연결하지 못했어요. 키를 확인해 주세요."
        }
    }

    private func disconnect() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await scheduleStore.deleteAgentKey()
            isConnected = false
            models = []
            usage = nil
        } catch {
            errorMessage = "연결 해지에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    private func loadConnectedContent() async {
        isLoadingDetails = true
        detailErrorMessage = nil
        defer { isLoadingDetails = false }

        do {
            models = try await scheduleStore.agentModels()
            if !models.contains(where: { $0.id == selectedModel }), let first = models.first {
                selectedModel = first.id
                CloudAgentModelPreference.selected = first.id
            }
        } catch {
            models = []
            detailErrorMessage = "모델 목록을 불러오지 못했어요."
        }

        do {
            usage = try await scheduleStore.agentUsage()
        } catch {
            usage = nil
            detailErrorMessage = [detailErrorMessage, "사용량을 불러오지 못했어요."]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }

    private func modelPrice(_ model: AgentModelDTO) -> String {
        "in \(usd(model.promptPricePerM, digits: 2)) · out \(usd(model.completionPricePerM, digits: 2)) /1M"
    }

    private func usageCost(_ cost: Double) -> String {
        usd(cost, digits: 6)
    }

    private func usd(_ value: Double, digits: Int) -> String {
        "$" + String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, value)
    }

    private func usageDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}

private struct MCPToolIdentityRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: ConnectionIcon
    let title: String
    let summary: String

    var body: some View {
        HStack(spacing: 12) {
            ConnectionMark(icon: icon)
            VStack(alignment: .leading, spacing: 4) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(title)
                        .font(MemdoTypography.action)
                    ConnectionBadge(title: "MCP")
                } else {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(MemdoTypography.action)
                        ConnectionBadge(title: "MCP")
                    }
                }
                Text(summary)
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("기본 보관") {
                    LabeledContent("활성 일정", value: "계정 유지 기간")
                    LabeledContent("삭제 일정", value: "30일")
                    LabeledContent("AI 계획 초안", value: "24시간")
                    LabeledContent("원문 AI 프롬프트", value: "기본 미저장")
                }
                Section("내가 통제하는 정보") {
                    Label("AI·알림·캘린더 동의는 각각 철회", systemImage: "hand.raised")
                    Label("연결 해제 시 외부 토큰 즉시 폐기", systemImage: "key.slash")
                    Label("AI 기록 삭제 요청 제공", systemImage: "trash")
                }
            }
            .memdoSystemList()
            .navigationTitle("개인정보 및 데이터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
    }
}

private struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var granted = AIConsent.granted

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("이 항목은 설정에서 별도로 연결하는 Memdo Agent 기준입니다.")
                        .font(MemdoTypography.footnote)
                        .foregroundStyle(MemdoTheme.secondaryInk)

                    Toggle(isOn: $granted) {
                        RoutineLabel(
                            icon: "sparkles",
                            title: "Memdo Agent 사용",
                            detail: "끄면 Agent가 응답하지 않아요"
                        )
                    }
                    .memdoToggle()
                    .onChange(of: granted) { _, newValue in
                        AIConsent.granted = newValue
                    }
                }
                Section("Memdo Agent가 보는 정보") {
                    Label("일정 제목", systemImage: "textformat")
                    Label("시작·종료 시간", systemImage: "clock")
                }
                Section("Memdo Agent가 보지 않는 정보") {
                    Label("위치와 메모", systemImage: "lock")
                    Label("연결하지 않은 외부 데이터", systemImage: "lock")
                }
                Section("실행 원칙") {
                    Label("일정 변경은 확인 후 실행", systemImage: "checkmark.shield")
                }
                Section("붙여넣기로 일정 만들기는 별도입니다") {
                    Text("텍스트를 붙여넣어 일정을 만드는 기능은 기기 안에서만 처리돼요(온디바이스). 이땐 붙여넣은 내용 전체(위치·메모 포함 가능)를 읽지만, 기기 밖으로 전송되지 않습니다.")
                        .font(MemdoTypography.footnote)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }
            .memdoSystemList()
            .navigationTitle("AI 데이터 접근")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
    }
}

// MARK: - Guest Upgrade

private struct GuestUpgradeRow: View {
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(MemdoTypography.title2)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("게스트 모드")
                        .font(MemdoTypography.action)
                    Text("계정을 연결하면 데이터가 영구 보관돼요")
                        .font(MemdoTypography.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }

            Button(action: onUpgrade) {
                Label("계정 연결하기", systemImage: "arrow.up.circle.fill")
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        MemdoTheme.accent,
                        in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
        .memdoSettingsRow()
    }
}

private struct GuestUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MemdoSession.self) private var session

    var body: some View {
        MemdoSignInView(
            session: session,
            gateTitle: "계정 연결하기",
            gateSubtitle: "지금까지의 기록이 그대로 유지돼요.\n모든 기기에서 동기화도 바로 시작돼요."
        )
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(MemdoTypography.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .signedIn { dismiss() }
        }
        .memdoSheetPresentation([.large])
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String?
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        icon: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MemdoMetrics.sectionContentSpacing) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.ink)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let subtitle {
                    Text(subtitle)
                        .font(MemdoTypography.footnote)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
                VStack(spacing: 0) { content }
                    .padding(.horizontal, 12)
                    .background(
                        MemdoTheme.surface,
                        in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                            .stroke(MemdoTheme.outline.opacity(0.35), lineWidth: 0.5)
                    }
            }
        }
    }
}
