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

// MARK: - Schedule Proposal (Tool result)

/// Resolves an agent-supplied date token ("today" | "tomorrow" | "yyyy-MM-dd")
/// to a local calendar day. Shared by ProposedScheduleDraft and
/// AgentScheduleUpdateProposal so the two proposal kinds agree on what these
/// tokens mean.
func resolveAgentDateToken(_ token: String) -> Date {
    let cal = Calendar.current
    switch token {
    case "today":    return cal.startOfDay(for: .now)
    case "tomorrow": return cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
    default:
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: token).map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: .now)
    }
}

/// Parses an agent-supplied "HH:mm" time onto the given day.
func parseAgentTime(_ s: String, on date: Date) -> Date? {
    let parts = s.split(separator: ":").compactMap { Int($0) }
    guard parts.count >= 2 else { return nil }
    return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
}

/// "오늘"/"내일"/"M월 d일" for an agent-supplied date token. Shared by
/// ProposedScheduleDraft and AgentScheduleUpdateProposal so both proposal
/// kinds render dates identically.
func displayAgentDateToken(_ token: String) -> String {
    switch token {
    case "today":    return "오늘"
    case "tomorrow": return "내일"
    default:
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일"
        return f.string(from: resolveAgentDateToken(token))
    }
}

struct ProposedScheduleDraft: Sendable, Equatable {
    let title: String
    let dateString: String          // "today" | "tomorrow" | "yyyy-MM-dd"
    let startTimeString: String?    // "HH:mm"
    let endTimeString: String?      // "HH:mm"
    let isTask: Bool
    let note: String?

    var displayDate: String { displayAgentDateToken(dateString) }

    var displayTime: String {
        if isTask { return "할 일" }
        guard let start = startTimeString else { return "시간 미정" }
        return start + (endTimeString.map { " – \($0)" } ?? "")
    }

    func scheduledDate() -> Date { resolveAgentDateToken(dateString) }

    func toScheduleDetail(calendar: ScheduleCalendar) -> ScheduleDetail {
        let date    = scheduledDate()
        let startAt = startTimeString.flatMap { parseAgentTime($0, on: date) }
        let endAt   = endTimeString.flatMap   { parseAgentTime($0, on: date) }
        return ScheduleDetail(
            scheduledDate: date,
            startAt: startAt, endAt: endAt,
            title: title, memo: note ?? "",
            kind: isTask ? .task : .event,
            calendar: calendar,
            timeBucket: startAt.map(ScheduleTimeBucket.inferred) ?? .anytime
        )
    }

    /// Resolved (start, end) for a timed proposal, or nil for a task/all-day
    /// item with nothing to conflict-check against. `end` falls back to a
    /// 1-hour block when the model omitted an end time, matching how a bare
    /// start time is treated elsewhere in the app.
    func resolvedInterval() -> (start: Date, end: Date)? {
        guard !isTask, let startTimeString else { return nil }
        let date = scheduledDate()
        guard let start = parseAgentTime(startTimeString, on: date) else { return nil }
        let end = endTimeString.flatMap { parseAgentTime($0, on: date) } ?? start.addingTimeInterval(3_600)
        return (start, end)
    }
}

@MainActor
@Observable
final class AgentScheduleProposal {
    var draft: ProposedScheduleDraft?
    /// Title of a conflicting existing item, set by ProposeScheduleTool's own
    /// reflection step (see call(arguments:)) so ProposedScheduleCard can warn
    /// before the user approves, rather than only after saving.
    var conflictTitle: String?
    /// True when the conflict check itself couldn't be verified server-side
    /// (see CloudProposedScheduleDTO.conflictCheckFailed) -- shown as its own
    /// warning rather than silently treated as "no conflict."
    var conflictCheckFailed: Bool = false
    func propose(_ d: ProposedScheduleDraft, conflictTitle: String? = nil, conflictCheckFailed: Bool = false) {
        draft = d
        self.conflictTitle = conflictTitle
        self.conflictCheckFailed = conflictCheckFailed
    }
    func clear() { draft = nil; conflictTitle = nil; conflictCheckFailed = false }
}

/// Pending state for an Agent proposal to complete, move, or delete an
/// EXISTING item (propose_schedule_update), mirroring AgentScheduleProposal's
/// shape for creates. `id` is the real todos.id the server echoed back from
/// search_schedules, not a client-generated value. Cloud-only for now --
/// propose_schedule_update has no on-device tool equivalent yet.
@MainActor
@Observable
final class AgentScheduleUpdateProposal {
    var id: String?
    var action: String?           // "complete" | "reschedule" | "delete"
    var title: String?
    var dateString: String?       // reschedule only
    var startTimeString: String?  // reschedule only
    var endTimeString: String?    // reschedule only
    var conflictTitle: String?
    var conflictCheckFailed: Bool = false

    var isPending: Bool { id != nil }

    var displayActionLabel: String {
        switch action {
        case "complete":   return "완료 처리"
        case "reschedule": return "일정 변경"
        case "delete":     return "삭제"
        default:           return "변경"
        }
    }

    var displayDate: String? {
        guard action == "reschedule", let dateString else { return nil }
        return displayAgentDateToken(dateString)
    }

    func propose(
        id: String,
        action: String,
        title: String,
        dateString: String?,
        startTimeString: String?,
        endTimeString: String?,
        conflictTitle: String?,
        conflictCheckFailed: Bool
    ) {
        self.id = id
        self.action = action
        self.title = title
        self.dateString = dateString
        self.startTimeString = startTimeString
        self.endTimeString = endTimeString
        self.conflictTitle = conflictTitle
        self.conflictCheckFailed = conflictCheckFailed
    }

    func clear() {
        id = nil
        action = nil
        title = nil
        dateString = nil
        startTimeString = nil
        endTimeString = nil
        conflictTitle = nil
        conflictCheckFailed = false
    }
}

@available(iOS 26, *)
struct ProposeScheduleTool: Tool {
    let name = "proposeSchedule"
    let description = "Proposes a new schedule or task to the user for confirmation. Use this whenever the user wants to create, add, or make a new schedule or task."

    @Generable
    struct Arguments: Sendable {
        @Guide(description: "Schedule title in Korean")
        let title: String
        @Guide(description: "Date: 'today', 'tomorrow', or yyyy-MM-dd")
        let date: String
        @Guide(description: "Start time HH:mm. Empty string for tasks")
        let startTime: String
        @Guide(description: "End time HH:mm. Empty string for tasks")
        let endTime: String
        @Guide(description: "true for a to-do task with no fixed time, false for timed event")
        let isTask: Bool
        @Guide(description: "Optional memo or note. Empty string if none")
        let note: String
    }

    /// Minimal, Sendable view of an existing schedule -- just enough to
    /// conflict-check and name the conflicting item, not the full model.
    struct ExistingItem: Sendable {
        let title: String
        let scheduledDate: Date
        let startAt: Date?
        let endAt: Date?
    }

    let proposal: AgentScheduleProposal
    let existing: [ExistingItem]

    func call(arguments: Arguments) async throws -> String {
        let draft = ProposedScheduleDraft(
            title:           arguments.title,
            dateString:      arguments.date,
            startTimeString: arguments.startTime.isEmpty ? nil : arguments.startTime,
            endTimeString:   arguments.endTime.isEmpty   ? nil : arguments.endTime,
            isTask:          arguments.isTask,
            note:            arguments.note.isEmpty       ? nil : arguments.note
        )
        // Reflection step: check the proposal against the real schedule
        // before handing it back, instead of presenting it uncritically.
        let conflict = conflictingItem(for: draft)
        await proposal.propose(draft, conflictTitle: conflict?.title)

        guard let conflict else {
            return "'\(draft.title)' 일정을 제안했습니다."
        }
        return "'\(draft.title)' 일정을 제안했습니다. 주의: 같은 시간에 이미 '\(conflict.title)' 일정이 있어요."
    }

    private func conflictingItem(for draft: ProposedScheduleDraft) -> ExistingItem? {
        guard let (start, end) = draft.resolvedInterval() else { return nil }
        return existing.first { item in
            guard let itemStart = item.startAt, let itemEnd = item.endAt else { return false }
            return start < itemEnd && end > itemStart
        }
    }
}

// MARK: - Free Slot Tool

@available(iOS 26, *)
struct FindFreeSlotTool: Tool {
    struct ScheduleInterval: Sendable {
        let scheduledDate: Date
        let startAt: Date?
        let endAt: Date?
    }

    let name        = "findFreeSlots"
    let description = "Finds available free time blocks in the user's calendar. Call this when the user asks to find free time, an open slot, or where to fit a new event."

    @Generable
    struct Arguments: Sendable {
        @Guide(description: "Date scope — one of: 'today', 'tomorrow', 'this_week', or a specific yyyy-MM-dd")
        let scope: String
        @Guide(description: "Required free-slot length in minutes, e.g. 30, 60, 90")
        let durationMinutes: Int
        @Guide(description: "Earliest start time HH:mm, e.g. '09:00'. Empty string = no preference.")
        let windowStart: String
        @Guide(description: "Latest end time HH:mm, e.g. '21:00'. Empty string = no preference.")
        let windowEnd: String
    }

    let snapshot: [ScheduleInterval]

    func call(arguments: Arguments) async throws -> String {
        let dates    = expandScope(arguments.scope)
        let duration = TimeInterval(max(15, arguments.durationMinutes) * 60)

        var lines: [String] = []
        for date in dates {
            let busyOnDay = snapshot.filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) }
            let slots = freeSlots(on: date, busy: busyOnDay, duration: duration,
                                  wStart: arguments.windowStart, wEnd: arguments.windowEnd)
            guard !slots.isEmpty else { continue }
            lines.append("\(dateLabel(date)): \(slots.map(formatInterval).joined(separator: ", "))")
        }

        return lines.isEmpty ? "요청한 조건에 맞는 빈 시간을 찾지 못했어요." : lines.joined(separator: "\n")
    }

    private func expandScope(_ scope: String) -> [Date] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: .now)
        switch scope {
        case "today":     return [today]
        case "tomorrow":  return [cal.date(byAdding: .day, value: 1, to: today) ?? today]
        case "this_week": return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        default:
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return [f.date(from: scope).map { cal.startOfDay(for: $0) } ?? today]
        }
    }

    private func freeSlots(on date: Date, busy: [ScheduleInterval],
                           duration: TimeInterval, wStart: String, wEnd: String) -> [DateInterval] {
        let cal    = Calendar.current
        let start  = timeFrom(wStart, on: date) ?? cal.date(bySettingHour: 8,  minute: 0, second: 0, of: date)!
        let end    = timeFrom(wEnd,   on: date) ?? cal.date(bySettingHour: 22, minute: 0, second: 0, of: date)!

        let busyRanges: [DateInterval] = busy
            .compactMap { s in
                guard let s1 = s.startAt, let e1 = s.endAt, e1 > s1 else { return nil }
                return DateInterval(start: s1, end: e1)
            }
            .sorted { $0.start < $1.start }

        var slots:  [DateInterval] = []
        var cursor: Date           = start

        for range in busyRanges {
            guard range.start > cursor else { cursor = max(cursor, range.end); continue }
            if range.start.timeIntervalSince(cursor) >= duration {
                slots.append(DateInterval(start: cursor, duration: duration))
            }
            cursor = max(cursor, range.end)
        }
        if end.timeIntervalSince(cursor) >= duration {
            slots.append(DateInterval(start: cursor, duration: duration))
        }

        return Array(slots.prefix(3))
    }

    private func timeFrom(_ hhmm: String, on date: Date) -> Date? {
        guard !hhmm.isEmpty else { return nil }
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }

    private func formatInterval(_ interval: DateInterval) -> String {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "ko_KR")
        f.dateFormat = "H:mm"
        let endTime  = interval.start.addingTimeInterval(interval.duration)
        return "\(f.string(from: interval.start))–\(f.string(from: endTime))"
    }

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)    { return "오늘" }
        if cal.isDateInTomorrow(date) { return "내일" }
        let f = DateFormatter()
        f.locale     = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일(E)"
        return f.string(from: date)
    }
}

// MARK: - Update Schedule Tool

/// On-device counterpart to the cloud propose_schedule_update tool --
/// completes, reschedules, or deletes an EXISTING item. Unlike the cloud
/// path (which resolves ids via a separate search_schedules round trip),
/// buildScheduleContext() never puts ids in the model's text context, so
/// the model can only refer to an item by title. This tool resolves that
/// title against the in-memory snapshot itself instead of asking the model
/// for an id it was never given.
@available(iOS 26, *)
struct UpdateScheduleTool: Tool {
    struct ExistingItem: Sendable {
        let id: String
        let title: String
        let scheduledDate: Date
        let startAt: Date?
        let endAt: Date?
    }

    let name = "updateSchedule"
    let description = "Proposes completing, rescheduling, or deleting an EXISTING schedule or task for the user to confirm. Use this when the user wants to mark something done, move it, or remove it -- do not just describe it in text. Identify the item by the title as it appears in the current context."

    @Generable
    struct Arguments: Sendable {
        @Guide(description: "The title of the existing schedule/task, as seen in the current context")
        let title: String
        @Guide(description: "One of: complete, reschedule, delete")
        let action: String
        @Guide(description: "New date for reschedule: 'today', 'tomorrow', or yyyy-MM-dd. Empty string if not rescheduling")
        let date: String
        @Guide(description: "New start time HH:mm for reschedule. Empty string if not rescheduling or no fixed time")
        let startTime: String
        @Guide(description: "New end time HH:mm for reschedule. Empty string if none")
        let endTime: String
    }

    let proposal: AgentScheduleUpdateProposal
    let existing: [ExistingItem]

    func call(arguments: Arguments) async throws -> String {
        guard let match = bestMatch(for: arguments.title) else {
            return "'\(arguments.title)'과(와) 일치하는 일정을 찾지 못했어요."
        }

        var conflict: ExistingItem?
        if arguments.action == "reschedule", !arguments.date.isEmpty, !arguments.startTime.isEmpty {
            let day = resolveAgentDateToken(arguments.date)
            if let start = parseAgentTime(arguments.startTime, on: day) {
                let end = arguments.endTime.isEmpty
                    ? start.addingTimeInterval(3_600)
                    : (parseAgentTime(arguments.endTime, on: day) ?? start.addingTimeInterval(3_600))
                conflict = conflictingItem(excluding: match.id, start: start, end: end)
            }
        }

        await proposal.propose(
            id: match.id,
            action: arguments.action,
            title: match.title,
            dateString: arguments.date.isEmpty ? nil : arguments.date,
            startTimeString: arguments.startTime.isEmpty ? nil : arguments.startTime,
            endTimeString: arguments.endTime.isEmpty ? nil : arguments.endTime,
            conflictTitle: conflict?.title,
            conflictCheckFailed: false
        )

        guard let conflict else {
            return "'\(match.title)' 항목에 대한 변경을 제안했습니다."
        }
        return "'\(match.title)' 항목에 대한 변경을 제안했습니다. 주의: 같은 시간에 이미 '\(conflict.title)' 일정이 있어요."
    }

    private func bestMatch(for title: String) -> ExistingItem? {
        let needle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let exact = existing.first(where: { $0.title == needle }) { return exact }
        return existing.first {
            $0.title.localizedCaseInsensitiveContains(needle) || needle.localizedCaseInsensitiveContains($0.title)
        }
    }

    private func conflictingItem(excluding id: String, start: Date, end: Date) -> ExistingItem? {
        existing.first { item in
            guard item.id != id, let itemStart = item.startAt, let itemEnd = item.endAt else { return false }
            return start < itemEnd && end > itemStart
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

private struct AgentSheetHeader: View {
    let context: AgentContext
    var hasStarted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(context.displayTitle) 문맥 사용 중", systemImage: "sparkles")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.brand)
            if !hasStarted {
                Text("무엇을 정리할까요?")
                    .font(MemdoTypography.detailTitle)
                Text("오늘 일정을 바탕으로 대화할 수 있어요. 질문하거나 요청해보세요.")
                    .font(MemdoTypography.subtitle)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
    }
}

private struct AgentUserBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(MemdoTypography.subtitle)
            .foregroundStyle(MemdoTheme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MemdoTheme.accent, in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct AgentQuickActions: View {
    let context: AgentContext
    let hasSchedulesToday: Bool
    let onSelect: (String) -> Void

    private var prompts: [(String, String)] {
        AgentPrompts.quickActions(for: context, hasSchedulesToday: hasSchedulesToday)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("빠른 요청")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.secondaryInk)

            VStack(spacing: 0) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { index, item in
                    Button { onSelect(item.1) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .font(MemdoTypography.captionEmphasis)
                                .foregroundStyle(MemdoTheme.brand)
                                .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.0)
                                    .font(MemdoTypography.action)
                                Text(item.1)
                                    .font(MemdoTypography.caption)
                                    .foregroundStyle(MemdoTheme.secondaryInk)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(MemdoTheme.ink)
                        .padding(.horizontal, MemdoMetrics.rowInset)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < prompts.count - 1 {
                        Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                    }
                }
            }
            .memdoRowGroup()
        }
    }
}

private struct AgentResponse: View {
    let message: AgentMessage
    var onRetry: (() -> Void)? = nil

    private var accentColor: Color {
        message.isError ? .red : MemdoTheme.brand
    }

    private var isToolPhase: Bool {
        message.isStreaming && message.text.isEmpty && message.toolHint != nil
    }

    private var headerLabel: String {
        if message.isError                              { return "오류" }
        if isToolPhase                                  { return "실행 중" }
        if message.isStreaming && message.text.isEmpty  { return "생각 중…" }
        return "Agent"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 6) {
                if isToolPhase {
                    Image(systemName: "gearshape.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                        .symbolEffect(.pulse)
                } else if message.isStreaming && message.text.isEmpty {
                    TypingDotsView()
                } else if message.isError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "sparkle")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                }
                Text(headerLabel)
                    .font(MemdoTypography.captionEmphasis)
                    .foregroundStyle(accentColor)
            }

            // Tool hint
            if let hint = message.toolHint, message.text.isEmpty {
                Text(hint)
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }

            // Main content — markdown-rendered
            if !message.text.isEmpty {
                AgentMarkdownText(text: message.text)
                    .font(MemdoTypography.subtitle)
                    .foregroundStyle(message.isError ? .red : MemdoTheme.ink)
                    .textSelection(.enabled)
            }

            // Retry
            if message.isError, let onRetry {
                Button(action: onRetry) {
                    Label("다시 시도", systemImage: "arrow.clockwise")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, MemdoMetrics.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accentColor)
                .frame(width: 3)
        }
        .contextMenu {
            if !message.text.isEmpty {
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("복사하기", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

/// Line-based Markdown renderer for Agent responses.
/// `AttributedString(markdown:)` with `.inlineOnlyPreservingWhitespace`
/// (used directly on the whole message before this) parses inline emphasis
/// ("**bold**") correctly but has no concept of block-level list markers --
/// a line starting with "* " or "- " comes through as a literal asterisk
/// followed by the (correctly bold-rendered) rest of the line, which is
/// exactly the raw-looking output reported from a real model response. This
/// classifies each line first, renders list lines as an actual bullet row,
/// and still inline-parses each line's own text the same way as before.
struct AgentMarkdownText: View {
    let text: String

    struct Line: Identifiable, Equatable {
        let id: Int
        let isListItem: Bool
        let content: String
    }

    /// Exposed for testing the classification independent of the view body.
    static func lines(for text: String) -> [Line] {
        text.components(separatedBy: "\n").enumerated().map { index, raw in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                return Line(id: index, isListItem: true, content: String(trimmed.dropFirst(2)))
            }
            return Line(id: index, isListItem: false, content: raw)
        }
    }

    /// Exposed for testing inline-markdown parsing independent of the view body.
    static func inlineAttributed(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    private var lines: [Line] { Self.lines(for: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines) { line in
                if line.content.isEmpty {
                    Color.clear.frame(height: 6)
                } else if line.isListItem {
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundStyle(MemdoTheme.secondaryInk)
                        Text(Self.inlineAttributed(line.content))
                    }
                } else {
                    Text(Self.inlineAttributed(line.content))
                }
            }
        }
    }
}

private struct TypingDotsView: View {
    @State private var active = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(MemdoTheme.brand)
                    .frame(width: 6, height: 6)
                    .scaleEffect(active ? 1.0 : 0.3)
                    .opacity(active ? 1.0 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18),
                        value: active
                    )
            }
        }
        .onAppear { active = true }
    }
}

// MARK: - Proposed Schedule Card

private struct ProposedScheduleCard: View {
    let draft: ProposedScheduleDraft
    var conflictTitle: String? = nil
    var conflictCheckFailed: Bool = false
    let onConfirm: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("일정 제안", systemImage: "calendar.badge.plus")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.brand)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.ink)

                HStack(spacing: 10) {
                    Label(draft.displayDate, systemImage: "calendar")
                    Label(draft.displayTime,
                          systemImage: draft.isTask ? "checkmark.circle" : "clock")
                }
                .font(MemdoTypography.caption)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .lineLimit(1)

                if let note = draft.note, !note.isEmpty {
                    Text(note)
                        .font(MemdoTypography.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .lineLimit(2)
                }

                // Reflection result: ProposeScheduleTool already checked this
                // against the real schedule -- surfaced here so approval is an
                // informed choice, not just a rubber stamp.
                if let conflictTitle {
                    Label("같은 시간에 '\(conflictTitle)' 일정이 있어요", systemImage: "exclamationmark.triangle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if conflictCheckFailed {
                    Label("기존 일정을 확인하지 못했어요 — 저장 전 직접 확인해주세요", systemImage: "questionmark.circle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    Label("저장하기", systemImage: "checkmark")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.accent,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDecline) {
                    Text("취소")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MemdoTheme.outline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(MemdoTheme.brandSoft,
                    in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                .stroke(MemdoTheme.brand.opacity(0.2), lineWidth: 0.5)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }
}

/// Confirmation card for propose_schedule_update (complete/reschedule/delete
/// an EXISTING item) -- shared by both the cloud path and UpdateScheduleTool
/// (on-device), since both funnel into the same AgentScheduleUpdateProposal.
private struct ProposedScheduleUpdateCard: View {
    let proposal: AgentScheduleUpdateProposal
    let onConfirm: () -> Void
    let onDecline: () -> Void

    private var icon: String {
        switch proposal.action {
        case "complete":   return "checkmark.circle"
        case "reschedule": return "calendar.badge.clock"
        case "delete":     return "trash"
        default:           return "pencil"
        }
    }

    private var confirmLabel: String {
        proposal.action == "delete" ? "삭제하기" : "적용하기"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(proposal.displayActionLabel) 제안", systemImage: icon)
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.brand)

            VStack(alignment: .leading, spacing: 6) {
                Text(proposal.title ?? "일정")
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.ink)

                if proposal.action == "reschedule", let displayDate = proposal.displayDate {
                    HStack(spacing: 10) {
                        Label(displayDate, systemImage: "calendar")
                        if let start = proposal.startTimeString {
                            Label(start + (proposal.endTimeString.map { " – \($0)" } ?? ""), systemImage: "clock")
                        }
                    }
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .lineLimit(1)
                }

                // Reflection result, same convention as ProposedScheduleCard
                // above -- surfaced before approval, not only after applying.
                if let conflictTitle = proposal.conflictTitle {
                    Label("같은 시간에 '\(conflictTitle)' 일정이 있어요", systemImage: "exclamationmark.triangle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if proposal.conflictCheckFailed {
                    Label("기존 일정을 확인하지 못했어요 — 적용 전 직접 확인해주세요", systemImage: "questionmark.circle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    Label(confirmLabel, systemImage: "checkmark")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.accent,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDecline) {
                    Text("취소")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MemdoTheme.outline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(MemdoTheme.brandSoft,
                    in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                .stroke(MemdoTheme.brand.opacity(0.2), lineWidth: 0.5)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }
}

// MARK: - Composer

private struct AgentComposer: View {
    @Binding var text: String
    var isLoading: Bool = false
    let onSend: () -> Void

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("어떤 일을 정리할까요?", text: $text)
                .onSubmit(onSend)
                .disabled(isLoading)
                .padding(.leading, MemdoMetrics.rowInset)
                .frame(minHeight: MemdoMetrics.touchTarget)

            Button(action: onSend) {
                if isLoading {
                    ProgressView()
                        .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(isEmpty ? MemdoTheme.secondaryInk : MemdoTheme.brand)
                        .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
                        .contentShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(isEmpty || isLoading)
            .accessibilityLabel("요청 보내기")
        }
        .padding(4)
        .memdoFloatingSurface(cornerRadius: MemdoMetrics.groupRadius)
    }
}
