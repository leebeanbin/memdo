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
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var dailySummary = true
    @State private var planningPromptEnabled = true
    @State private var notifications = true
    @State private var summaryTime = Calendar.current.date(from: DateComponents(hour: SettingsDefaults.summaryHour, minute: SettingsDefaults.summaryMinute)) ?? .now
    @State private var promptTime = Calendar.current.date(from: DateComponents(hour: SettingsDefaults.promptHour)) ?? .now
    @State private var presentedSheet: SettingsSheet?
    @State private var showsWallpaperPreview = false
    @State private var showsSignOutConfirmation = false
    @State private var showsDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
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
                            // "로그아웃" reads oddly for a guest who never
                            // signed in -- this clears the anonymous session/
                            // local data, so name it after what it does
                            // (matches the confirmation dialog below). Found
                            // during founder dogfooding.
                            Text("게스트 데이터 초기화")
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

                // Guests have no real account (no email/external identity) to
                // delete -- "게스트 데이터 초기화" above already clears local
                // data with the same warning. Showing this too was redundant and
                // routed to the backend DELETE /account (Apple revoke, etc.)
                // for a session that was never meant to hit that path. Found
                // during founder dogfooding.
                if session.phase != .guest {
                    Divider()
                    Button { showsDeleteAccountConfirmation = true } label: {
                        HStack {
                            Text("계정 삭제")
                                .font(MemdoTypography.subtitle)
                                .foregroundStyle(.red)
                            Spacer()
                            if isDeletingAccount {
                                ProgressView()
                            } else {
                                Image(systemName: "trash")
                                    .font(MemdoTypography.captionEmphasis)
                                    .foregroundStyle(.red)
                                    .accessibilityHidden(true)
                            }
                        }
                        .memdoSettingsRow()
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isBusy || isDeletingAccount)

                    if let deleteAccountErrorMessage {
                        Divider()
                        Label(deleteAccountErrorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(MemdoTypography.caption)
                            .foregroundStyle(.red)
                            .memdoSettingsRow()
                    }
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
            session.phase == .guest ? "게스트 데이터를 초기화할까요?" : "로그아웃 하시겠어요?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button(session.phase == .guest ? "초기화" : "로그아웃", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(session.phase == .guest
                ? "저장된 일정과 기록이 모두 삭제됩니다."
                : "이 기기에서 로그아웃합니다.")
        }
        .confirmationDialog(
            "계정을 삭제하시겠어요?",
            isPresented: $showsDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("계정 삭제", role: .destructive) {
                Task { await deleteAccountAndSignOut() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("계정과 저장된 모든 일정·기록이 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없어요.")
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

    /// DELETE /account (Epic L) -- the backend attempts Apple token
    /// revocation and cascades all application data itself, fail-open on
    /// the revoke step; this only needs to call it once and then return
    /// the app to unauthenticated state via the existing signOut()-driven
    /// reactive reset (scheduleStore/preferencesStore/workoutStore already
    /// reset themselves via MemdoSession.observe()'s authStateChanges
    /// handler -- no separate local-clear code needed here).
    private func deleteAccountAndSignOut() async {
        isDeletingAccount = true
        deleteAccountErrorMessage = nil
        defer { isDeletingAccount = false }
        do {
            try await scheduleStore.deleteAccount()
            await session.signOut()
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
        }
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

enum ConnectionIcon {
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
                // Long values (e.g. "시작 오전 9:00 · 정리 오후 11:24") wrap
                // with no explicit alignment here, so they inherited the
                // row's .leading default and broke awkwardly mid-value.
                // Found during founder dogfooding.
                Text(value)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .multilineTextAlignment(.trailing)
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

struct MCPToolIdentityRow: View {
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
