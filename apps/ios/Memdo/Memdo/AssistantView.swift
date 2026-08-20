import SwiftUI
import FoundationModels

// MARK: - Message model

struct AgentMessage: Identifiable, Equatable {
    var id = UUID()
    var role: Role
    var text: String
    var isStreaming: Bool = false
    var isError: Bool = false
    var toolHint: String? = nil   // shown while a tool is executing and no text yet

    enum Role: Equatable { case user, assistant }
}

// MARK: - Cloud model preference

/// The selected model id comes from the authenticated agent-models endpoint.
/// The backend remains the source of truth and validates this value again.
enum CloudAgentModelPreference {
    static let defaultID = "openai/gpt-5.4-mini"
    private static let key = "memdo.v1.cloudAgentModel"

    static var selected: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - AI consent

/// Backs the toggle in AIConsentSheet (SettingsView.swift). Defaults to
/// `true` (opt-out, not opt-in) -- the sheet's own copy already describes
/// consent in withdrawal terms ("AI·알림·캘린더 동의는 각각 철회"), and the
/// Agent feature has been usable with no gate at all up to this point, so an
/// opt-in default would silently lock existing users out with no onboarding
/// flow prompting them to turn it back on.
enum AIConsent {
    private static let key = "memdo.v1.aiConsentGranted"

    static var granted: Bool {
        get { (UserDefaults.standard.object(forKey: key) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Context

enum AgentContext {
    case today
    case calendar
    case settings
    case todaySummary
    case weekReview
    case monthReview

    var displayTitle: String {
        switch self {
        case .today: "오늘"
        case .calendar: "캘린더"
        case .settings: "설정"
        case .todaySummary: "하루 정리"
        case .weekReview: "지난 7일 회고"
        case .monthReview: "지난 30일 회고"
        }
    }
}

// MARK: - Agent Sheet

struct AgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @Binding var composer: String
    @Binding var messages: [AgentMessage]

    let context: AgentContext

    @State private var _sessionBacking: AnyObject? = nil
    @State private var isLoading = false
    @State private var showSessionGapNotice = false
    @State private var showsResetConfirmation = false
    @State private var proposal = AgentScheduleProposal()
    @State private var updateProposal = AgentScheduleUpdateProposal()
    /// Tracked so a new send can cancel whatever's still in flight instead of
    /// leaving it to keep streaming into a `messages[last]` index that's
    /// since shifted out from under it.
    @State private var activeTask: Task<Void, Never>?
    /// True once we've determined the cloud path is needed (no on-device
    /// model on this OS/device) but no OpenRouter key is connected yet --
    /// prompts the user to connect immediately instead of only after they
    /// send a message and hit a dead-end error.
    @State private var needsCloudConnection = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
                        AgentSheetHeader(context: context, hasStarted: !messages.isEmpty)

                        messageList

                        Color.clear.frame(height: 1).id("agentBottom")
                    }
                    .padding(MemdoMetrics.pagePadding)
                }
                .onChange(of: messages) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("agentBottom", anchor: .bottom)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MemdoTheme.background)
            .safeAreaInset(edge: .bottom) {
                AgentComposer(text: $composer, isLoading: isLoading, onSend: send)
                    .padding(.horizontal, MemdoMetrics.pagePadding)
                    .padding(.vertical, 6)
            }
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("새 대화", systemImage: "square.and.pencil") {
                        showsResetConfirmation = true
                    }
                    .disabled(messages.isEmpty || isLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .confirmationDialog(
            "새 대화를 시작할까요?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("새 대화 시작", role: .destructive) { resetConversation() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 대화 내용이 삭제됩니다.")
        }
        .task {
            if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
                let hadHistory = !messages.isEmpty
                if typedSession == nil {
                    _sessionBacking = LanguageModelSession(
                        tools: [
                            ProposeScheduleTool(proposal: proposal, existing: existingItemsSnapshot()),
                            FindFreeSlotTool(snapshot: scheduleSnapshot()),
                            UpdateScheduleTool(proposal: updateProposal, existing: updatableItemsSnapshot())
                        ],
                        instructions: agentInstructions()
                    )
                    if hadHistory { showSessionGapNotice = true }
                }
                typedSession?.prewarm()
            } else {
                // No on-device model on this OS/device -- every send() call
                // will need the cloud path, so check the connection now
                // rather than waiting for the user to type something first.
                needsCloudConnection = (try? await scheduleStore.agentKeyConnected()) != true
            }
        }
        .onChange(of: proposal.draft) { _, draft in
            guard draft != nil else { return }
            if let last = messages.indices.last,
               messages[last].isStreaming, messages[last].text.isEmpty {
                messages[last].toolHint = "일정을 제안하는 중..."
            }
        }
        .sheet(isPresented: $needsCloudConnection) {
            CloudAgentConnectionSheet()
        }
        .memdoSheetPresentation([.medium, .large])
    }

    @ViewBuilder
    private var messageList: some View {
        if messages.isEmpty && proposal.draft == nil {
            AgentQuickActions(context: context, hasSchedulesToday: hasSchedulesToday, onSelect: selectQuickAction)
        } else {
            if showSessionGapNotice { sessionGapBanner }
            ForEach(messages) { message in
                if message.role == .user {
                    AgentUserBubble(text: message.text)
                } else {
                    AgentResponse(message: message, onRetry: message.isError ? { retry() } : nil)
                }
            }
            if let draft = proposal.draft {
                ProposedScheduleCard(
                    draft: draft,
                    conflictTitle: proposal.conflictTitle,
                    conflictCheckFailed: proposal.conflictCheckFailed
                ) {
                    confirmProposal(draft)
                } onDecline: {
                    withAnimation(.easeOut(duration: 0.2)) { proposal.clear() }
                }
            }
            if updateProposal.isPending {
                ProposedScheduleUpdateCard(proposal: updateProposal) {
                    confirmScheduleUpdateProposal()
                } onDecline: {
                    declineScheduleUpdateProposal()
                }
            }
        }
    }

    private var sessionGapBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(MemdoTypography.caption)
            Text("새 세션이 시작됐어요. 이전 대화는 참고만 가능해요.")
                .font(MemdoTypography.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("새 대화") {
                resetConversation()
                showSessionGapNotice = false
            }
            .font(MemdoTypography.captionEmphasis)
            .foregroundStyle(MemdoTheme.brand)
        }
        .foregroundStyle(MemdoTheme.secondaryInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MemdoTheme.brandSoft, in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
    }

    private func selectQuickAction(_ prompt: String) {
        composer = prompt
        send()
    }

    /// Consent-gated message shown instead of dispatching to either path
    /// when AIConsent.granted is off -- checked here rather than per-tool
    /// since the sheet's copy describes the whole Agent, not individual
    /// tools, and a half-gated chat (some tools silently no-op) would be
    /// more confusing than not responding at all.
    private var consentDeclinedMessage: AgentMessage {
        AgentMessage(
            role: .assistant,
            text: "설정 > 개인정보 및 데이터 > AI 데이터 접근에서 Memdo Agent 사용을 켜야 답할 수 있어요.",
            isError: true
        )
    }

    /// Set isLoading synchronously, before scheduling the Task -- sendWithCloudAgent/
    /// sendWithFoundationModels used to set this at the top of their own
    /// (async) bodies, which left a window where a second call in the same
    /// run loop pass would still see isLoading == false and pass the guard
    /// in send(). Two overlapping streams then both wrote into
    /// `messages[last]`, which shifts as each one appends its own
    /// messages -- the runaway/duplicated-output bug reported from tapping a
    /// quick action. Shared by send()/retry() so both stay in sync.
    private func dispatchToModel(_ prompt: String) {
        isLoading = true
        activeTask?.cancel()
        // On-device when this OS/device actually has it available; otherwise
        // the cloud path (BYOK via OpenRouter, see agent-cloud-chat) covers
        // both older devices and open-ended requests the fixed-shape
        // on-device tools aren't suited for.
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            activeTask = Task { await sendWithFoundationModels(prompt) }
        } else {
            activeTask = Task { await sendWithCloudAgent(prompt) }
        }
    }

    private func send() {
        let prompt = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isLoading else { return }
        composer = ""
        messages.append(AgentMessage(role: .user, text: prompt))
        guard AIConsent.granted else {
            messages.append(consentDeclinedMessage)
            return
        }
        dispatchToModel(prompt)
    }

    /// Turns already-settled messages into the flat history the stateless
    /// cloud endpoint expects (it has no session of its own -- every call
    /// resends the conversation so far, same as every other request in this
    /// app being independently authenticated rather than session-based).
    private func cloudHistory() -> [AgentChatTurnDTO] {
        messages
            .filter { !$0.isStreaming && !$0.isError }
            .map { AgentChatTurnDTO(role: $0.role == .user ? "user" : "assistant", content: $0.text) }
    }

    private func sendWithCloudAgent(_ prompt: String) async {
        let history = cloudHistory()
        // isLoading is already true -- send()/retry() set it synchronously
        // before scheduling this Task.
        let placeholder = AgentMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(placeholder)
        let messageID = placeholder.id
        // Every mutation below targets messageID specifically rather than
        // "whatever's currently last" -- if this call gets cancelled by a
        // newer send(), messages.last has since moved on to that newer
        // call's own placeholder, and indices-last writes here would land on
        // the wrong message (this was the actual bug behind quick actions
        // appearing to pour out endless/duplicated text).
        defer {
            isLoading = false
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].isStreaming = false
            }
        }

        do {
            let result = try await scheduleStore.agentCloudChat(
                message: prompt,
                history: history,
                model: CloudAgentModelPreference.selected
            ) { delta in
                if let index = messages.firstIndex(where: { $0.id == messageID }) {
                    messages[index].text += delta
                }
            }
            if let proposed = result.proposedSchedule {
                proposal.propose(
                    ProposedScheduleDraft(
                        title: proposed.title,
                        dateString: proposed.date,
                        startTimeString: proposed.startTime?.isEmpty == false ? proposed.startTime : nil,
                        endTimeString: proposed.endTime?.isEmpty == false ? proposed.endTime : nil,
                        isTask: proposed.isTask,
                        note: proposed.note?.isEmpty == false ? proposed.note : nil
                    ),
                    conflictTitle: proposed.conflictTitle,
                    conflictCheckFailed: proposed.conflictCheckFailed ?? false
                )
            }
            if let proposedUpdate = result.proposedScheduleUpdate {
                updateProposal.propose(
                    id: proposedUpdate.id,
                    action: proposedUpdate.action,
                    title: proposedUpdate.title,
                    dateString: proposedUpdate.date,
                    startTimeString: proposedUpdate.startTime?.isEmpty == false ? proposedUpdate.startTime : nil,
                    endTimeString: proposedUpdate.endTime?.isEmpty == false ? proposedUpdate.endTime : nil,
                    conflictTitle: proposedUpdate.conflictTitle,
                    conflictCheckFailed: proposedUpdate.conflictCheckFailed ?? false
                )
            }
        } catch ScheduleAPIError.server(_, let code, _, _) where code == "RESOURCE_NOT_FOUND" {
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].text = "이 기기에서 Agent를 쓰려면 클라우드 연결이 필요해요."
                messages[index].isError = true
            }
            // Open the connect sheet right here instead of leaving the user
            // to find Settings > 클라우드 Agent on their own.
            needsCloudConnection = true
        } catch is CancellationError {
            // A newer send()/resetConversation() cancelled this one -- its
            // own placeholder gets cleaned up by its own defer/error path,
            // not this one. Silently stop.
        } catch {
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].text = "오류가 발생했어요. 다시 시도해주세요."
                messages[index].isError = true
            }
        }
    }

    private func resetConversation() {
        activeTask?.cancel()
        activeTask = nil
        composer = ""
        messages = []
        _sessionBacking = nil
        isLoading = false
        showSessionGapNotice = false
        proposal.clear()
        updateProposal.clear()
    }

    private func confirmProposal(_ draft: ProposedScheduleDraft) {
        let cal = scheduleStore.calendars.first(where: { $0.provider == .memdo })
                  ?? scheduleStore.calendars.first
        if let cal {
            scheduleStore.save(draft.toScheduleDetail(calendar: cal))
            messages.append(AgentMessage(role: .assistant, text: "'\(draft.title)' 일정을 저장했어요 ✓"))
        }
        withAnimation(.easeOut(duration: 0.2)) { proposal.clear() }
    }

    /// Applies an approved propose_schedule_update by dispatching to the
    /// same ScheduleModel entry points the manual UI already uses (toggle/
    /// move/delete) -- this never talks to the network directly, so it picks
    /// up the exact same offline-outbox/optimistic-rollback/version-conflict
    /// handling those already have, instead of a second, divergent path.
    private func confirmScheduleUpdateProposal() {
        guard let idString = updateProposal.id, let id = UUID(uuidString: idString),
              let action = updateProposal.action else { return }
        let title = updateProposal.title ?? "일정"

        switch action {
        case "complete":
            // toggleDone silently no-ops for a non-task item (events have no
            // completion state in this app) -- check first so the confirmation
            // message never claims a change that didn't happen.
            if scheduleStore.schedules.first(where: { $0.id == id })?.kind == .task {
                scheduleStore.toggleDone(id: id)
                messages.append(AgentMessage(role: .assistant, text: "'\(title)' 완료 처리했어요 ✓"))
            } else {
                messages.append(AgentMessage(role: .assistant, text: "'\(title)'은(는) 완료 처리할 수 없는 일정이에요.", isError: true))
            }
        case "reschedule":
            let day = resolveAgentDateToken(updateProposal.dateString ?? "today")
            var startAt: Date?
            var endAt: Date?
            if let startString = updateProposal.startTimeString,
               let start = parseAgentTime(startString, on: day) {
                startAt = start
                endAt = updateProposal.endTimeString.flatMap { parseAgentTime($0, on: day) }
                    ?? start.addingTimeInterval(3_600)
            }
            scheduleStore.move(id: id, to: day, startAt: startAt, endAt: endAt)
            messages.append(AgentMessage(role: .assistant, text: "'\(title)' 일정을 옮겼어요 ✓"))
        case "delete":
            scheduleStore.delete(id: id)
            messages.append(AgentMessage(role: .assistant, text: "'\(title)' 일정을 삭제했어요 ✓"))
        default:
            break
        }
        withAnimation(.easeOut(duration: 0.2)) { updateProposal.clear() }
    }

    private func declineScheduleUpdateProposal() {
        withAnimation(.easeOut(duration: 0.2)) { updateProposal.clear() }
    }

    private func retry() {
        guard !isLoading else { return }
        guard let lastUserMsg = messages.dropLast().last(where: { $0.role == .user }) else { return }
        messages.removeLast()
        guard AIConsent.granted else {
            messages.append(consentDeclinedMessage)
            return
        }
        dispatchToModel(lastUserMsg.text)
    }

    private var hasSchedulesToday: Bool {
        let cal = Calendar.current
        return scheduleStore.schedules.contains { cal.isDateInToday($0.scheduledDate) }
    }

    @available(iOS 26, *)
    private func scheduleSnapshot() -> [FindFreeSlotTool.ScheduleInterval] {
        scheduleStore.schedules.map {
            .init(scheduledDate: $0.scheduledDate, startAt: $0.startAt, endAt: $0.endAt)
        }
    }

    @available(iOS 26, *)
    private func existingItemsSnapshot() -> [ProposeScheduleTool.ExistingItem] {
        scheduleStore.schedules.map {
            .init(title: $0.title, scheduledDate: $0.scheduledDate, startAt: $0.startAt, endAt: $0.endAt)
        }
    }

    @available(iOS 26, *)
    private func updatableItemsSnapshot() -> [UpdateScheduleTool.ExistingItem] {
        scheduleStore.schedules.map {
            .init(id: $0.id.uuidString, title: $0.title, scheduledDate: $0.scheduledDate, startAt: $0.startAt, endAt: $0.endAt)
        }
    }

    // MARK: - FoundationModels

    @available(iOS 26, *)
    private var typedSession: LanguageModelSession? {
        _sessionBacking as? LanguageModelSession
    }

    @available(iOS 26, *)
    private func sendWithFoundationModels(_ prompt: String) async {
        // isLoading is already true -- send()/retry() set it synchronously
        // before scheduling this Task. Reset unconditionally on every exit
        // path, including the early-return guards below (previously this was
        // set *after* those guards, which was fine when it lived here -- now
        // that the caller sets it before dispatch, this function must be the
        // one to always clear it again).
        defer { isLoading = false }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            messages.append(AgentMessage(
                role: .assistant,
                text: unavailabilityMessage(model.availability),
                isError: true
            ))
            return
        }
        if typedSession == nil {
            _sessionBacking = LanguageModelSession(
                tools: [
                    ProposeScheduleTool(proposal: proposal, existing: existingItemsSnapshot()),
                    FindFreeSlotTool(snapshot: scheduleSnapshot())
                ],
                instructions: agentInstructions()
            )
        }
        guard let session = typedSession else { return }

        let placeholder = AgentMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(placeholder)
        let messageID = placeholder.id
        // Targets messageID specifically, not "whatever's currently last" --
        // see the matching comment in sendWithCloudAgent for why.
        defer {
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].isStreaming = false
            }
        }

        do {
            let stream = session.streamResponse(to: prompt)
            for try await snapshot in stream {
                // FoundationModels' own tool-calling loop has no iteration
                // cap we control (unlike the cloud path's MAX_TOOL_ITERATIONS)
                // -- this is the only place a stuck/looping generation can be
                // stopped, via a new send() or resetConversation() cancelling
                // this Task.
                if Task.isCancelled { break }
                if let index = messages.firstIndex(where: { $0.id == messageID }) {
                    messages[index].text = snapshot.content
                }
            }
        } catch is CancellationError {
            // Cancelled by a newer send()/resetConversation() -- nothing to
            // report, this placeholder is being torn down or superseded.
        } catch {
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].text = "오류가 발생했어요. 다시 시도해주세요."
                messages[index].isError = true
            }
        }
    }

    @available(iOS 26, *)
    private func agentInstructions() -> String {
        return """
            \(AgentPrompts.onDeviceInstructions)
            Current view context: \(context.displayTitle)
            \(buildScheduleContext())
            """
    }

    // Injects different schedule data depending on which tab opened the agent.
    private func buildScheduleContext() -> String {
        let cal = Calendar.current
        let now = Date()
        let schedules = scheduleStore.schedules

        switch context {
        case .today, .todaySummary:
            let today = schedules.filter { cal.isDateInToday($0.scheduledDate) }
            guard !today.isEmpty else { return "" }
            let done = today.filter { $0.isDone }
            let pending = today.filter { !$0.isDone }
            var parts: [String] = []
            if !pending.isEmpty {
                parts.append("오늘 남은 일정:\n" + pending.prefix(10).map { "- \($0.title) \($0.displayTime)" }.joined(separator: "\n"))
            }
            if !done.isEmpty {
                parts.append("오늘 완료:\n" + done.prefix(5).map { "- \($0.title)" }.joined(separator: "\n"))
            }
            return parts.joined(separator: "\n\n")

        case .calendar:
            // Includes kind (할 일/일정) and completion so "미완료 할 일을
            // 빈 시간에 제안해줘" (a quick action below) has something to
            // actually filter on -- a bare title+time list can't answer
            // that prompt at all.
            guard let weekEnd = cal.date(byAdding: .day, value: 7, to: now) else { return "" }
            let week = schedules.filter { $0.scheduledDate >= now && $0.scheduledDate <= weekEnd }
            guard !week.isEmpty else { return "" }
            return "이번 주 일정:\n" + week.prefix(15).map {
                let kind = $0.kind == .task ? "할 일" : "일정"
                let status = $0.isDone ? ", 완료" : ""
                return "- [\(kind)\(status)] \($0.title) \($0.displayTime)"
            }.joined(separator: "\n")

        case .weekReview:
            guard let weekStart = cal.date(byAdding: .day, value: -7, to: now) else { return "" }
            let past = schedules.filter { $0.scheduledDate >= weekStart && $0.scheduledDate <= now }
            guard !past.isEmpty else { return "" }
            let doneCount = past.filter { $0.isDone }.count
            return "지난 7일 일정 \(past.count)개 (완료 \(doneCount)개):\n"
                + past.prefix(15).map { "- [\($0.isDone ? "✓" : " ")] \($0.title)" }.joined(separator: "\n")

        case .monthReview:
            // Used to be just a bare count ("지난 30일 일정 47개 (완료
            // 32개)") with no titles at all -- the "놓친 작업의 공통점을
            // 찾아줘" quick action below asks the model to find a pattern
            // across titles it was never actually given. Same
            // title-list shape as weekReview, just a smaller slice (most
            // recent first) since a month can have far more items than a
            // rolling 15-line context is meant for.
            guard let monthStart = cal.date(byAdding: .day, value: -30, to: now) else { return "" }
            let past = schedules.filter { $0.scheduledDate >= monthStart && $0.scheduledDate <= now }
            guard !past.isEmpty else { return "" }
            let doneCount = past.filter { $0.isDone }.count
            let recent = past.sorted { $0.scheduledDate > $1.scheduledDate }
            return "지난 30일 일정 \(past.count)개 (완료 \(doneCount)개), 최근 항목:\n"
                + recent.prefix(15).map { "- [\($0.isDone ? "✓" : " ")] \($0.title)" }.joined(separator: "\n")

        case .settings:
            return ""
        }
    }

    @available(iOS 26, *)
    private func unavailabilityMessage(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available: return ""
        case .unavailable(.deviceNotEligible):
            return "이 기기는 Apple Intelligence를 지원하지 않아요."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "설정 > Apple Intelligence에서 Apple Intelligence를 활성화해주세요."
        case .unavailable(.modelNotReady):
            return "모델을 준비 중이에요. 잠시 후 다시 시도해주세요."
        default:
            return "지금은 Agent를 사용할 수 없어요."
        }
    }
}
