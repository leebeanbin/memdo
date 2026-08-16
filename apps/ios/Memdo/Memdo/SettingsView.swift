import AuthenticationServices
import SwiftUI

private enum SettingsDefaults {
    static let summaryHour = 21
    static let summaryMinute = 30
    static let promptHour = 9
    static let keywordMaxLength = 30
    static let keywordMaxCount = 5
    static let suggestedKeywords = ["AI", "SwiftUI", "제품 디자인", "서울 로컬", "스타트업"]
    static let preferencePushDebounce: Duration = .milliseconds(500)
}

struct SettingsView: View {
    let coachMarkTarget: CoachMarkTarget?
    let onStartCoachMarkTour: ((CoachMarkTour) -> Void)?
    @Environment(MemdoSession.self) private var session
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showKeywordHint = false
    @State private var dailySummary = true
    @State private var notifications = true
    @State private var summaryTime = Calendar.current.date(from: DateComponents(hour: SettingsDefaults.summaryHour, minute: SettingsDefaults.summaryMinute)) ?? .now
    @State private var promptTime = Calendar.current.date(from: DateComponents(hour: SettingsDefaults.promptHour)) ?? .now
    // Persisted locally only: the backend preferences contract has no keyword
    // column yet (moves server-side with B9 briefing work).
    @State private var briefingKeywords: Set<String>
    @State private var customKeywords: [String]
    @State private var briefingCategories: Set<String>
    @State private var presentedSheet: SettingsSheet?
    @State private var googleCalendarConnected: Bool? = nil
    // Keychain-backed (see SlackNotifier), refreshed on appear and whenever
    // the Slack sheet is dismissed -- @AppStorage can't watch Keychain.
    @State private var slackConnected = false
    @State private var showsSignOutConfirmation = false
    @State private var summaryTimePushTask: Task<Void, Never>?
    @State private var promptTimePushTask: Task<Void, Never>?
    @AppStorage(
        MemdoWidgetStorage.hideContentKey,
        store: UserDefaults(suiteName: MemdoWidgetStorage.suiteName)
    ) private var hideWidgetContent = false

    private static let selectedKeywordsKey   = "briefing-selected-keywords"
    private static let customKeywordsKey    = "briefing-custom-keywords"
    private static let selectedCategoriesKey = "briefing-selected-categories"

    init(coachMarkTarget: CoachMarkTarget? = nil, onStartCoachMarkTour: ((CoachMarkTour) -> Void)? = nil) {
        self.coachMarkTarget = coachMarkTarget
        self.onStartCoachMarkTour = onStartCoachMarkTour
        let defaults = UserDefaults.standard
        // nil means "never saved" (seed the suggested defaults); an empty array
        // is a deliberate deselect-all and must stay empty.
        _briefingKeywords = State(
            initialValue: defaults.stringArray(forKey: Self.selectedKeywordsKey)
                .map(Set.init) ?? ["AI", "제품 디자인"]
        )
        _customKeywords = State(
            initialValue: defaults.stringArray(forKey: Self.customKeywordsKey) ?? []
        )
        _briefingCategories = State(
            initialValue: defaults.stringArray(forKey: Self.selectedCategoriesKey).map(Set.init) ?? []
        )
    }

    var body: some View {
        MemdoPage(
            title: "설정",
            subtitle: "Memdo를 나에게 맞게 조정하세요",
            eyebrow: "나만의 Memdo",
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
                        .font(.caption)
                        .foregroundStyle(.red)
                        .memdoSettingsRow()
                }
                .buttonStyle(.plain)
            }

            SettingsGroup(title: "하루") {
                Toggle("오늘 요약", isOn: $dailySummary)
                    .memdoToggle()
                    .memdoSettingsRow()
                if dailySummary {
                    Divider()
                    SettingsTimePicker(title: "요약 시간", selection: $summaryTime)
                }
                Divider()
                SettingsTimePicker(title: "계획 알림", selection: $promptTime)
                Divider()
                Toggle("알림", isOn: $notifications)
                    .memdoToggle()
                    .memdoSettingsRow()
                Divider()
                Button { presentedSheet = .briefingKeywords } label: {
                    let total = briefingCategories.count + briefingKeywords.count
                    SettingsDisclosureRow(
                        title: "브리핑 관심사",
                        value: total > 0 ? "분야 \(briefingCategories.count) · 키워드 \(briefingKeywords.count)" : "설정 안 함"
                    )
                }
                .buttonStyle(.plain)
            }
            .id(CoachMarkTarget.settingsDay)
            .coachMarkTarget(.settingsDay)

            SettingsGroup(title: "위젯") {
                Button { presentedSheet = .wallpaperPreview } label: {
                    SettingsDisclosureRow(title: "전체 달력 배경화면", value: "미리보기 · 저장")
                }
                .buttonStyle(.plain)
            }
            .id(CoachMarkTarget.settingsWidget)
            .coachMarkTarget(.settingsWidget)

            SettingsGroup(
                title: "내 Agent 연결",
                subtitle: "서비스는 MCP 도구로 연결되고, 실행은 항상 내 확인을 거쳐요."
            ) {
                Button { presentedSheet = .googleCalendar } label: {
                    AgentConnectionRow(
                        icon: .asset("GoogleCalendar"),
                        title: "Google Calendar",
                        capability: "일정 읽기 전용",
                        status: googleCalendarConnected == nil ? "확인 중" : googleCalendarConnected == true ? "연결됨" : "미연결",
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
                Divider()
                Button { presentedSheet = .aiConsent } label: {
                    AgentConnectionRow(
                        icon: .memdo,
                        title: "Memdo Agent",
                        capability: "일정 제목 · 시간만 사용",
                        status: "범위 설정"
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
            .id(CoachMarkTarget.settingsConnections)
            .coachMarkTarget(.settingsConnections)

            SettingsGroup(title: "계정") {
                if session.phase == .guest {
                    GuestUpgradeRow(onUpgrade: { presentedSheet = .guestUpgrade })
                    Divider()
                    Button { showsSignOutConfirmation = true } label: {
                        HStack {
                            Text("로그아웃")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.caption.weight(.semibold))
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
                            .font(.title2)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.accountLabel)
                                .font(.subheadline.weight(.semibold))
                            Text(session.providerLabel)
                                .font(.caption)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                        Spacer()
                        Button { showsSignOutConfirmation = true } label: {
                            Text("로그아웃")
                                .font(.caption.weight(.semibold))
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
                        .font(.caption)
                        .foregroundStyle(.red)
                        .memdoSettingsRow()
                }
            }

            if let onStartCoachMarkTour {
                SettingsGroup(title: "도움말") {
                    Button {
                        onStartCoachMarkTour(.app)
                    } label: {
                        HStack {
                            Label("앱 투어 다시 보기", systemImage: "map")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
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
            case .aiConsent:
                AIConsentSheet()
            case .briefingKeywords:
                BriefingKeywordsSheet(
                    selectedCategories: $briefingCategories,
                    selectedKeywords: $briefingKeywords,
                    customKeywords: $customKeywords
                )
            case .privacy:
                PrivacySheet()
            case .slack:
                SlackConnectionSheet()
            case .googleCalendar:
                GoogleCalendarConnectionSheet()
            case .guestUpgrade:
                GuestUpgradeSheet()
            case .wallpaperPreview:
                WallpaperPreviewSheet()
            }
        }
        .sensoryFeedback(.selection, trigger: briefingKeywords)
        .sensoryFeedback(.selection, trigger: briefingCategories)
        .onChange(of: briefingKeywords) { _, value in
            UserDefaults.standard.set(Array(value).sorted(), forKey: Self.selectedKeywordsKey)
        }
        .onChange(of: customKeywords) { _, value in
            UserDefaults.standard.set(value, forKey: Self.customKeywordsKey)
        }
        .onChange(of: briefingCategories) { _, value in
            UserDefaults.standard.set(Array(value).sorted(), forKey: Self.selectedCategoriesKey)
        }
        .task { await loadPreferences() }
        .task { await loadGoogleCalendarStatus() }
        .task { slackConnected = !SlackNotifier.webhookURL.isEmpty }
        .onChange(of: presentedSheet) { oldSheet, sheet in
            guard sheet == nil else { return }
            if oldSheet == .briefingKeywords {
                withAnimation(reduceMotion ? nil : .easeIn) { showKeywordHint = true }
            }
            Task { await loadGoogleCalendarStatus() }
            slackConnected = !SlackNotifier.webhookURL.isEmpty
        }
        .overlay(alignment: .bottom) { keywordHint }
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
        notifications = preferences.notificationsEnabled
        hideWidgetContent = preferences.hideWidgetContent
        if let time = ClockString.date(preferences.dailyReviewTime) { summaryTime = time }
        if let time = ClockString.date(preferences.planningPromptTime) { promptTime = time }
    }

    private func push(_ transform: @escaping (inout UserPreferences) -> Void) {
        guard session.preferencesStore != nil else { return }
        Task { await session.preferencesStore?.update(transform) }
    }

    private func loadGoogleCalendarStatus() async {
        googleCalendarConnected = (try? await scheduleStore.googleCalendarStatus())?.connected == true
    }

    @ViewBuilder
    private var keywordHint: some View {
        if showKeywordHint {
            Label("오늘 탭의 브리핑에 바로 적용됐어요.", systemImage: "checkmark.circle")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                )
                .padding(.horizontal, MemdoMetrics.pagePadding)
                .padding(.bottom, MemdoMetrics.tabBarClearance)
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: MemdoMetrics.bannerDismissDuration)
                    withAnimation(reduceMotion ? nil : .easeOut) { showKeywordHint = false }
                }
        }
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
                    .font(.subheadline.weight(.semibold))
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ConnectionMark(icon: icon)

            VStack(alignment: .leading, spacing: 4) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let badge {
                        ConnectionBadge(title: badge)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if let badge {
                            ConnectionBadge(title: badge)
                        }
                    }
                }
                Text(capability)
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                if dynamicTypeSize.isAccessibilitySize {
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }

            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(MemdoTheme.secondaryInk)
                .accessibilityHidden(true)
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
            .font(.caption2.bold())
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
                .font(.caption.bold())
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
                DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
            }
        }
        .memdoSettingsRow()
    }
}

private enum SettingsSheet: String, Identifiable {
    case aiConsent
    case briefingKeywords
    case googleCalendar
    case guestUpgrade
    case privacy
    case slack
    case wallpaperPreview
    var id: String { rawValue }
}

private struct BriefingKeywordsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategories: Set<String>
    @Binding var selectedKeywords: Set<String>
    @Binding var customKeywords: [String]
    @State private var draft = ""

    private static let suggestedKeywords = SettingsDefaults.suggestedKeywords

    private var keywordOptions: [String] {
        Self.suggestedKeywords + customKeywords.filter { !Self.suggestedKeywords.contains($0) }
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddKeyword: Bool {
        !normalizedDraft.isEmpty
            && normalizedDraft.count <= SettingsDefaults.keywordMaxLength
            && selectedKeywords.count < SettingsDefaults.keywordMaxCount
            && !keywordOptions.contains { $0.localizedCaseInsensitiveCompare(normalizedDraft) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {

                    // MARK: Category selection (primary)
                    Text("관심 분야를 선택하면 해당 RSS 뉴스를 가져와요.")
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.secondaryInk)

                    MemdoSection(title: "관심 분야") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(BriefingFeedCategory.allCases) { category in
                                MemdoChoiceButton(
                                    title: category.rawValue,
                                    isSelected: selectedCategories.contains(category.rawValue),
                                    action: { toggleCategory(category) }
                                )
                            }
                        }
                        .padding(.horizontal, MemdoMetrics.rowInset)
                        .padding(.vertical, 12)
                    }

                    // MARK: Keyword refinement (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("키워드 (선택 사항)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MemdoTheme.secondaryInk)
                        Text("키워드를 추가하면 해당 단어가 포함된 기사만 표시돼요.")
                            .font(.caption)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                    }

                    HStack(spacing: 8) {
                        TextField("키워드 입력", text: $draft)
                            .submitLabel(.done)
                            .onSubmit(addKeyword)
                        Button(action: addKeyword) {
                            MemdoIconButtonLabel(systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAddKeyword)
                        .accessibilityLabel("브리핑 키워드 추가")
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .frame(minHeight: MemdoMetrics.touchTarget)
                    .memdoFloatingSurface()

                    MemdoSection(title: "키워드", trailing: "\(selectedKeywords.count)/\(SettingsDefaults.keywordMaxCount)") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(keywordOptions, id: \.self) { keyword in
                                MemdoChoiceButton(
                                    title: keyword,
                                    isSelected: selectedKeywords.contains(keyword),
                                    action: { toggleKeyword(keyword) }
                                )
                            }
                        }
                    }
                }
                .padding(MemdoMetrics.pagePadding)
            }
            .background(MemdoTheme.background)
            .navigationTitle("브리핑 관심사")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
    }

    private func toggleCategory(_ category: BriefingFeedCategory) {
        withAnimation(.snappy(duration: 0.2)) {
            if selectedCategories.contains(category.rawValue) {
                selectedCategories.remove(category.rawValue)
            } else {
                selectedCategories.insert(category.rawValue)
            }
        }
    }

    private func addKeyword() {
        guard canAddKeyword else { return }
        customKeywords.append(normalizedDraft)
        selectedKeywords.insert(normalizedDraft)
        draft = ""
    }

    private func toggleKeyword(_ keyword: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if selectedKeywords.contains(keyword) {
                selectedKeywords.remove(keyword)
            } else if selectedKeywords.count < SettingsDefaults.keywordMaxCount {
                selectedKeywords.insert(keyword)
            }
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
                                .font(.caption.monospacedDigit())
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
                                .font(.caption)
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
                            .font(.caption.monospacedDigit())
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
                        .font(.subheadline.weight(.semibold))
                    ConnectionBadge(title: "MCP")
                } else {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        ConnectionBadge(title: "MCP")
                    }
                }
                Text(summary)
                    .font(.caption)
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("이 항목은 설정에서 별도로 연결하는 Memdo Agent 기준입니다.")
                        .font(.footnote)
                        .foregroundStyle(MemdoTheme.secondaryInk)
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
                        .font(.footnote)
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
                    .font(.title2)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("게스트 모드")
                        .font(.subheadline.weight(.semibold))
                    Text("계정을 연결하면 데이터가 영구 보관돼요")
                        .font(.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }

            Button(action: onUpgrade) {
                Label("계정 연결하기", systemImage: "arrow.up.circle.fill")
                    .font(.subheadline.weight(.semibold))
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
                    .font(.title3)
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
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        MemdoSection(title: title) {
            VStack(alignment: .leading, spacing: 8) {
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
                VStack(spacing: 0) { content }
                    .padding(.horizontal, 12)
                    .memdoRowGroup()
            }
        }
    }
}
