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

    /// nil until the sheet's .task runs -- AgentCoordinator owns runtime
    /// selection, execution lifecycle, and cancellation (previously done
    /// inline in this View via activeTask/_sessionBacking).
    @State private var coordinator: AgentCoordinator?
    @State private var isLoading = false
    @State private var showSessionGapNotice = false
    @State private var showsResetConfirmation = false
    @State private var proposal = AgentScheduleProposal()
    @State private var updateProposal = AgentScheduleUpdateProposal()
    /// The placeholder assistant bubble for whichever turn is currently in
    /// flight -- read by ingestCloudResult(_:), which CloudAgentRuntime
    /// calls back into after this View has moved on to constructing the
    /// next request, so it can't just close over a local messageID the way
    /// per-send closures do.
    @State private var currentAssistantMessageID: AgentMessage.ID?
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
            ensureCoordinator()
            if isOnDeviceAvailable() {
                let hadHistory = !messages.isEmpty
                if coordinator?.prewarmOnDevice() == true, hadHistory {
                    showSessionGapNotice = true
                }
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
                    conflictTitle: proposal.conflict?.title,
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

    /// Set isLoading synchronously, before scheduling the Task -- this used
    /// to be set at the top of the (async) send functions themselves, which
    /// left a window where a second call in the same run loop pass would
    /// still see isLoading == false and pass the guard in send(). Two
    /// overlapping streams then both wrote into `messages[last]`, which
    /// shifts as each one appends its own messages -- the runaway/
    /// duplicated-output bug reported from tapping a quick action. Shared
    /// by send()/retry() so both stay in sync.
    private func dispatchToModel(_ prompt: String) {
        isLoading = true
        ensureCoordinator()
        // Computed before appending the placeholder below -- agentConversationHistory's
        // precondition is that `messages.last` is the current turn (the user
        // message just appended by send()/retry()), not yet this turn's
        // still-empty assistant placeholder.
        let history = agentConversationHistory(from: messages)
        let placeholder = AgentMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(placeholder)
        let messageID = placeholder.id
        currentAssistantMessageID = messageID
        coordinator?.send(
            prompt: prompt,
            history: history,
            onDeviceAvailable: isOnDeviceAvailable()
        ) { event in
            self.handleCoordinatorEvent(event, messageID: messageID)
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

    private func isOnDeviceAvailable() -> Bool {
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// Builds the Coordinator once per sheet lifetime -- mirrors the old
    /// code's "only construct a session if one doesn't exist yet" but one
    /// level up, since AgentCoordinator now owns the runtime(s) instead of
    /// this View holding a LanguageModelSession directly.
    private func ensureCoordinator() {
        guard coordinator == nil else { return }
        var onDeviceFactory: (() -> AgentRuntime)?
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            onDeviceFactory = { self.makeOnDeviceRuntime() }
        }
        coordinator = AgentCoordinator(
            onDeviceRuntimeFactory: onDeviceFactory,
            cloudRuntime: CloudAgentRuntime(scheduleStore: scheduleStore) { result in
                self.ingestCloudResult(result)
            }
        )
    }

    @available(iOS 26, *)
    private func makeOnDeviceRuntime() -> AgentRuntime {
        OnDeviceAgentRuntime(
            tools: [
                ProposeScheduleTool(proposal: proposal, existing: existingItemsSnapshot()),
                FindFreeSlotTool(snapshot: scheduleSnapshot()),
                UpdateScheduleTool(proposal: updateProposal, existing: existingItemsSnapshot())
            ],
            instructions: agentInstructions()
        )
    }

    /// Every mutation here targets messageID specifically rather than
    /// "whatever's currently last" -- if this call gets cancelled by a newer
    /// send(), messages.last has since moved on to that newer call's own
    /// placeholder, and indices-last writes here would land on the wrong
    /// message (this was the actual bug behind quick actions appearing to
    /// pour out endless/duplicated text). AgentCoordinator never calls this
    /// for a superseded/cancelled turn (see AgentExecutionFailure's doc
    /// comment), so there's no cancellation case to handle here anymore.
    private func handleCoordinatorEvent(_ event: AgentCoordinatorEvent, messageID: AgentMessage.ID) {
        switch event {
        case .started:
            break
        case .textSnapshot(let text):
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].text = text
            }
        case .finished:
            isLoading = false
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].isStreaming = false
            }
        case .failed(let failure):
            isLoading = false
            guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
            messages[index].isStreaming = false
            switch failure {
            case .cloudConnectionRequired:
                messages[index].text = "이 기기에서 Agent를 쓰려면 클라우드 연결이 필요해요."
                messages[index].isError = true
                // Open the connect sheet right here instead of leaving the
                // user to find Settings > 클라우드 Agent on their own.
                needsCloudConnection = true
            case .runtimeFailure:
                messages[index].text = "오류가 발생했어요. 다시 시도해주세요."
                messages[index].isError = true
            }
        }
    }

    /// CloudAgentRuntime's onResult callback -- called once a cloud turn's
    /// result DTO is in, with currentAssistantMessageID pointing at that
    /// turn's placeholder (set synchronously by dispatchToModel right before
    /// the coordinator.send() call this is a side effect of, so it's still
    /// correct here: AgentCoordinator only ever has one turn in flight at a
    /// time).
    private func ingestCloudResult(_ result: AgentCloudChatResult) {
        guard let messageID = currentAssistantMessageID else { return }
        // Trust-boundary re-validation: agent-tool-contract.ts already
        // rejects an invalid date before staging server-side, so this
        // should be unreachable in production -- it defends against a
        // client/backend version skew (either side shipped
        // independently) rather than distrusting a healthy backend.
        // Never stage a proposal this client can't itself render/resolve
        // correctly (Issue A-04).
        //
        // Conflict identity (Issue C-04): the server's conflictTitle has
        // no stable id to compare against at confirm time, so it's not
        // used here -- instead this recomputes locally via
        // ConflictService against the current scheduleStore.schedules,
        // exactly like the on-device Tools already do at their own
        // staging point. That keeps both staging paths symmetric: an
        // AgentConflictSnapshot is always a local recomputation, never a
        // value trusted from the network. conflictCheckFailed is a
        // separate, server-only signal (a DB fetch failure a local
        // recomputation can't reproduce) and is passed through as-is.
        if let proposed = result.proposedSchedule {
            if AgentDateExpression(token: proposed.date) != nil {
                let draft = ProposedScheduleDraft(
                    title: proposed.title,
                    dateString: proposed.date,
                    startTimeString: proposed.startTime?.isEmpty == false ? proposed.startTime : nil,
                    endTimeString: proposed.endTime?.isEmpty == false ? proposed.endTime : nil,
                    isTask: proposed.isTask,
                    note: proposed.note?.isEmpty == false ? proposed.note : nil
                )
                let conflict = draft.resolvedInterval().flatMap { interval in
                    ConflictService.conflict(
                        for: AgentTimeRange(start: interval.start, end: interval.end),
                        in: existingItemsSnapshot()
                    )
                }
                proposal.propose(
                    draft,
                    conflict: conflict.map { AgentConflictSnapshot(id: $0.id, title: $0.title) },
                    conflictCheckFailed: proposed.conflictCheckFailed ?? false
                )
            } else {
                appendRecoverableErrorIfNoAssistantText(messageID: messageID)
            }
        }
        if let proposedUpdate = result.proposedScheduleUpdate {
            let dateIsValid = proposedUpdate.date.map { AgentDateExpression(token: $0) != nil } ?? true
            if dateIsValid {
                let conflict = rescheduleConflict(
                    action: proposedUpdate.action,
                    excludingId: proposedUpdate.id,
                    dateString: proposedUpdate.date,
                    startTimeString: proposedUpdate.startTime,
                    endTimeString: proposedUpdate.endTime
                )
                updateProposal.propose(
                    id: proposedUpdate.id,
                    action: proposedUpdate.action,
                    title: proposedUpdate.title,
                    dateString: proposedUpdate.date,
                    startTimeString: proposedUpdate.startTime?.isEmpty == false ? proposedUpdate.startTime : nil,
                    endTimeString: proposedUpdate.endTime?.isEmpty == false ? proposedUpdate.endTime : nil,
                    conflict: conflict.map { AgentConflictSnapshot(id: $0.id, title: $0.title) },
                    conflictCheckFailed: proposedUpdate.conflictCheckFailed ?? false
                )
            } else {
                appendRecoverableErrorIfNoAssistantText(messageID: messageID)
            }
        }
    }

    /// Computes the conflict (if any) for a reschedule's target date/time,
    /// or nil for non-reschedule actions or an unresolvable date/time --
    /// shared by cloud-response staging and confirm-time revalidation
    /// (Issue C-04) so both compute a reschedule's conflict identically.
    private func rescheduleConflict(
        action: String,
        excludingId: String,
        dateString: String?,
        startTimeString: String?,
        endTimeString: String?
    ) -> ConflictService.ExistingItem? {
        guard action == "reschedule",
              let dateString, let expr = AgentDateExpression(token: dateString),
              let startTimeString, !startTimeString.isEmpty,
              let start = parseAgentTime(startTimeString, on: expr.resolvedDate())
        else { return nil }
        let end = endTimeString.flatMap { parseAgentTime($0, on: expr.resolvedDate()) } ?? start.addingTimeInterval(3_600)
        return ConflictService.conflict(
            for: AgentTimeRange(start: start, end: end),
            excludingId: excludingId,
            in: existingItemsSnapshot()
        )
    }

    /// Only shown when there's no useful assistant text already on screen --
    /// the backend typically already told the model INVALID_AGENT_ARGUMENT,
    /// which usually produces its own clarifying reply in the streamed text,
    /// so adding a second error here on top of that would just duplicate it.
    private func appendRecoverableErrorIfNoAssistantText(messageID: AgentMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        guard messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages[index].text = "요청하신 내용을 정확히 이해하지 못했어요. 다시 말씀해 주시겠어요?"
        messages[index].isError = true
    }

    private func resetConversation() {
        // Cancel first, then discard the on-device runtime/session -- so
        // "새 대화" actually starts a fresh LanguageModelSession (and thus a
        // fresh conversation context) on the next send instead of
        // continuing the old one's.
        coordinator?.cancel()
        coordinator?.resetRuntime()
        composer = ""
        messages = []
        currentAssistantMessageID = nil
        isLoading = false
        showSessionGapNotice = false
        proposal.clear()
        updateProposal.clear()
    }

    private func confirmProposal(_ draft: ProposedScheduleDraft) {
        // Revalidate against the current local schedule before mutating
        // (Issue C-04) -- `proposal.conflict` may have been captured a while
        // ago at staging time (on-device: whenever the Tool/session was
        // constructed, not necessarily now; cloud: when the response
        // arrived), so this recomputes fresh and only proceeds if nothing
        // riskier than what the user already saw on the card is true now.
        let fresh = draft.resolvedInterval().flatMap { interval in
            ConflictService.conflict(
                for: AgentTimeRange(start: interval.start, end: interval.end),
                in: existingItemsSnapshot()
            )
        }
        let freshSnapshot = fresh.map { AgentConflictSnapshot(id: $0.id, title: $0.title) }
        switch conflictRevalidationDecision(staged: proposal.conflict, fresh: freshSnapshot) {
        case .refresh(let snapshot):
            // Don't mutate on this tap -- update the card in place (still
            // pending, @Observable re-renders it) and let the user approve
            // again having seen the new conflict.
            proposal.conflict = snapshot
            return
        case .proceed:
            break
        }

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
        guard let idString = updateProposal.id, let id = UUID(uuidString: idString) else { return }
        let title = updateProposal.title ?? "일정"

        // Both staging points (UpdateScheduleTool.call(arguments:) on-device,
        // the cloud-response staging block above) already validate action/
        // date before ever reaching updateProposal -- this guard should be
        // unreachable, but on failure it surfaces an explicit error rather
        // than silently doing nothing (the old `default: break`).
        guard let action = updateProposal.action.flatMap(AgentUpdateAction.init(rawValue:)) else {
            messages.append(AgentMessage(role: .assistant, text: "요청하신 작업을 처리하지 못했어요.", isError: true))
            withAnimation(.easeOut(duration: 0.2)) { updateProposal.clear() }
            return
        }

        switch action {
        case .complete:
            // toggleDone silently no-ops for a non-task item (events have no
            // completion state in this app) -- check first so the confirmation
            // message never claims a change that didn't happen.
            if scheduleStore.schedules.first(where: { $0.id == id })?.kind == .task {
                scheduleStore.toggleDone(id: id)
                messages.append(AgentMessage(role: .assistant, text: "'\(title)' 완료 처리했어요 ✓"))
            } else {
                messages.append(AgentMessage(role: .assistant, text: "'\(title)'은(는) 완료 처리할 수 없는 일정이에요.", isError: true))
            }
        case .reschedule:
            guard let dateString = updateProposal.dateString,
                  let expr = AgentDateExpression(token: dateString) else {
                messages.append(AgentMessage(role: .assistant, text: "옮길 날짜를 처리하지 못했어요.", isError: true))
                break
            }
            let day = expr.resolvedDate()
            var startAt: Date?
            var endAt: Date?
            if let startString = updateProposal.startTimeString,
               let start = parseAgentTime(startString, on: day) {
                startAt = start
                endAt = updateProposal.endTimeString.flatMap { parseAgentTime($0, on: day) }
                    ?? start.addingTimeInterval(3_600)
            }

            // Revalidate before mutating (Issue C-04) -- same contract as
            // confirmProposal(_:). excludingId: idString so the item being
            // moved never conflicts with its own (pre-move) row.
            let fresh = rescheduleConflict(
                action: action.rawValue,
                excludingId: idString,
                dateString: updateProposal.dateString,
                startTimeString: updateProposal.startTimeString,
                endTimeString: updateProposal.endTimeString
            )
            let freshSnapshot = fresh.map { AgentConflictSnapshot(id: $0.id, title: $0.title) }
            switch conflictRevalidationDecision(staged: updateProposal.conflict, fresh: freshSnapshot) {
            case .refresh(let snapshot):
                updateProposal.conflict = snapshot
                return
            case .proceed:
                break
            }

            scheduleStore.move(id: id, to: day, startAt: startAt, endAt: endAt)
            messages.append(AgentMessage(role: .assistant, text: "'\(title)' 일정을 옮겼어요 ✓"))
        case .delete:
            scheduleStore.delete(id: id)
            messages.append(AgentMessage(role: .assistant, text: "'\(title)' 일정을 삭제했어요 ✓"))
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

    /// Shared by ProposeScheduleTool (excludingId always nil -- new items
    /// never conflict-exclude anything) and UpdateScheduleTool (excludes the
    /// item being rescheduled by id) -- both now take the same
    /// ConflictService.ExistingItem shape. Not @available(iOS 26, *)-gated
    /// like scheduleSnapshot()/the Tools themselves -- ConflictService has no
    /// FoundationModels dependency, and this is also called from the cloud
    /// path (sendWithCloudAgent) and confirm-time revalidation
    /// (confirmProposal/confirmScheduleUpdateProposal), neither of which are
    /// iOS26-only.
    private func existingItemsSnapshot() -> [ConflictService.ExistingItem] {
        scheduleStore.schedules.map {
            .init(id: $0.id.uuidString, title: $0.title, startAt: $0.startAt, endAt: $0.endAt)
        }
    }

    // MARK: - FoundationModels

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
}
