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

/// Which OpenRouter model the cloud path requests. Must stay in sync with
/// ALLOWED_OPENROUTER_MODELS in agent-cloud-contract.ts -- the server
/// re-validates this list itself rather than trusting the client, so a
/// stale/tampered value here just gets rejected, not silently forwarded.
enum CloudAgentModelPreference {
    static let options: [(id: String, label: String)] = [
        ("openai/gpt-4o-mini", "GPT-4o mini (기본, 빠름)"),
        ("openai/gpt-4o", "GPT-4o"),
        ("anthropic/claude-3.5-sonnet", "Claude 3.5 Sonnet"),
        ("google/gemini-2.0-flash-001", "Gemini 2.0 Flash"),
    ]
    private static let key = "memdo.v1.cloudAgentModel"

    static var selected: String? {
        get { UserDefaults.standard.string(forKey: key) }
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
        case .todaySummary: "오늘 요약"
        case .weekReview: "지난 7일 회고"
        case .monthReview: "지난 30일 회고"
        }
    }
}

// MARK: - Schedule Proposal (Tool result)

struct ProposedScheduleDraft: Sendable, Equatable {
    let title: String
    let dateString: String          // "today" | "tomorrow" | "yyyy-MM-dd"
    let startTimeString: String?    // "HH:mm"
    let endTimeString: String?      // "HH:mm"
    let isTask: Bool
    let note: String?

    var displayDate: String {
        switch dateString {
        case "today":    return "오늘"
        case "tomorrow": return "내일"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "ko_KR")
            f.dateFormat = "M월 d일"
            return f.string(from: scheduledDate())
        }
    }

    var displayTime: String {
        if isTask { return "할 일" }
        guard let start = startTimeString else { return "시간 미정" }
        return start + (endTimeString.map { " – \($0)" } ?? "")
    }

    func scheduledDate() -> Date {
        let cal = Calendar.current
        switch dateString {
        case "today":    return cal.startOfDay(for: .now)
        case "tomorrow": return cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
        default:
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.date(from: dateString).map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: .now)
        }
    }

    func toScheduleDetail(calendar: ScheduleCalendar) -> ScheduleDetail {
        let date    = scheduledDate()
        let startAt = startTimeString.flatMap { parseTime($0, on: date) }
        let endAt   = endTimeString.flatMap   { parseTime($0, on: date) }
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
        guard let start = parseTime(startTimeString, on: date) else { return nil }
        let end = endTimeString.flatMap { parseTime($0, on: date) } ?? start.addingTimeInterval(3_600)
        return (start, end)
    }

    private func parseTime(_ s: String, on date: Date) -> Date? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
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
    func propose(_ d: ProposedScheduleDraft, conflictTitle: String? = nil) {
        draft = d
        self.conflictTitle = conflictTitle
    }
    func clear() { draft = nil; conflictTitle = nil }
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
            if #available(iOS 26, *) {
                let hadHistory = !messages.isEmpty
                if typedSession == nil {
                    _sessionBacking = LanguageModelSession(
                        tools: [
                            ProposeScheduleTool(proposal: proposal, existing: existingItemsSnapshot()),
                            FindFreeSlotTool(snapshot: scheduleSnapshot())
                        ],
                        instructions: agentInstructions()
                    )
                    if hadHistory { showSessionGapNotice = true }
                }
                typedSession?.prewarm()
            }
        }
        .onChange(of: proposal.draft) { _, draft in
            guard draft != nil else { return }
            if let last = messages.indices.last,
               messages[last].isStreaming, messages[last].text.isEmpty {
                messages[last].toolHint = "일정을 제안하는 중..."
            }
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
                ProposedScheduleCard(draft: draft, conflictTitle: proposal.conflictTitle) {
                    confirmProposal(draft)
                } onDecline: {
                    withAnimation(.easeOut(duration: 0.2)) { proposal.clear() }
                }
            }
        }
    }

    private var sessionGapBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
            Text("새 세션이 시작됐어요. 이전 대화는 참고만 가능해요.")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("새 대화") {
                resetConversation()
                showSessionGapNotice = false
            }
            .font(.caption.weight(.semibold))
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

    private func send() {
        let prompt = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isLoading else { return }
        composer = ""
        messages.append(AgentMessage(role: .user, text: prompt))
        // On-device when this OS/device actually has it available; otherwise
        // the cloud path (BYOK via OpenRouter, see agent-cloud-chat) covers
        // both older devices and open-ended requests the fixed-shape
        // on-device tools aren't suited for.
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            Task { await sendWithFoundationModels(prompt) }
        } else {
            Task { await sendWithCloudAgent(prompt) }
        }
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
        isLoading = true
        messages.append(AgentMessage(role: .assistant, text: "", isStreaming: true))
        defer {
            isLoading = false
            if let last = messages.indices.last, messages[last].isStreaming {
                messages[last].isStreaming = false
            }
        }

        do {
            let proposedSchedule = try await scheduleStore.agentCloudChat(
                message: prompt,
                history: history,
                model: CloudAgentModelPreference.selected
            ) { delta in
                if let last = messages.indices.last, messages[last].role == .assistant {
                    messages[last].text += delta
                }
            }
            if let proposed = proposedSchedule {
                proposal.propose(
                    ProposedScheduleDraft(
                        title: proposed.title,
                        dateString: proposed.date,
                        startTimeString: proposed.startTime?.isEmpty == false ? proposed.startTime : nil,
                        endTimeString: proposed.endTime?.isEmpty == false ? proposed.endTime : nil,
                        isTask: proposed.isTask,
                        note: proposed.note?.isEmpty == false ? proposed.note : nil
                    ),
                    conflictTitle: proposed.conflictTitle
                )
            }
        } catch ScheduleAPIError.server(_, let code, _, _) where code == "RESOURCE_NOT_FOUND" {
            if let last = messages.indices.last, messages[last].role == .assistant {
                messages[last].text = "이 기기에서 Agent를 쓰려면 클라우드 연결이 필요해요. 설정 > 클라우드 Agent에서 연결해 주세요."
                messages[last].isError = true
            }
        } catch {
            if let last = messages.indices.last, messages[last].role == .assistant {
                messages[last].text = "오류가 발생했어요. 다시 시도해주세요."
                messages[last].isError = true
            }
        }
    }

    private func resetConversation() {
        composer = ""
        messages = []
        _sessionBacking = nil
        isLoading = false
        showSessionGapNotice = false
        proposal.clear()
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

    private func retry() {
        guard !isLoading else { return }
        guard let lastUserMsg = messages.dropLast().last(where: { $0.role == .user }) else { return }
        messages.removeLast()
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            Task { await sendWithFoundationModels(lastUserMsg.text) }
        } else {
            Task { await sendWithCloudAgent(lastUserMsg.text) }
        }
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

    // MARK: - FoundationModels

    @available(iOS 26, *)
    private var typedSession: LanguageModelSession? {
        _sessionBacking as? LanguageModelSession
    }

    @available(iOS 26, *)
    private func sendWithFoundationModels(_ prompt: String) async {
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

        isLoading = true
        messages.append(AgentMessage(role: .assistant, text: "", isStreaming: true))

        defer {
            isLoading = false
            if let last = messages.indices.last, messages[last].isStreaming {
                messages[last].isStreaming = false
            }
        }

        do {
            let stream = session.streamResponse(to: prompt)
            for try await snapshot in stream {
                if let last = messages.indices.last, messages[last].role == .assistant {
                    messages[last].text = snapshot.content
                }
            }
        } catch {
            if let last = messages.indices.last, messages[last].role == .assistant {
                messages[last].text = "오류가 발생했어요. 다시 시도해주세요."
                messages[last].isError = true
            }
        }
    }

    @available(iOS 26, *)
    private func agentInstructions() -> String {
        return """
            The person’s locale is ko_KR. You MUST respond in Korean.
            You are Memdo’s personal schedule assistant. Be concise, warm, and practical.
            When the user wants to create, add, or make any new schedule or task, call the proposeSchedule tool — do not just describe it in text.
            When the user asks to find free time, an open slot, or where to fit something, call the findFreeSlots tool — do not guess from the context alone.
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
            guard let weekEnd = cal.date(byAdding: .day, value: 7, to: now) else { return "" }
            let week = schedules.filter { $0.scheduledDate >= now && $0.scheduledDate <= weekEnd }
            guard !week.isEmpty else { return "" }
            return "이번 주 일정:\n" + week.prefix(15).map { "- \($0.title) \($0.displayTime)" }.joined(separator: "\n")

        case .weekReview:
            guard let weekStart = cal.date(byAdding: .day, value: -7, to: now) else { return "" }
            let past = schedules.filter { $0.scheduledDate >= weekStart && $0.scheduledDate <= now }
            guard !past.isEmpty else { return "" }
            let doneCount = past.filter { $0.isDone }.count
            return "지난 7일 일정 \(past.count)개 (완료 \(doneCount)개):\n"
                + past.prefix(15).map { "- [\($0.isDone ? "✓" : " ")] \($0.title)" }.joined(separator: "\n")

        case .monthReview:
            guard let monthStart = cal.date(byAdding: .day, value: -30, to: now) else { return "" }
            let past = schedules.filter { $0.scheduledDate >= monthStart && $0.scheduledDate <= now }
            guard !past.isEmpty else { return "" }
            let doneCount = past.filter { $0.isDone }.count
            return "지난 30일 일정 \(past.count)개 (완료 \(doneCount)개)"

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
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoTheme.brand)
            if !hasStarted {
                Text("무엇을 정리할까요?")
                    .font(.title2.bold())
                Text("오늘 일정을 바탕으로 대화할 수 있어요. 질문하거나 요청해보세요.")
                    .font(.subheadline)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
    }
}

private struct AgentUserBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
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
        switch context {
        case .calendar: [
            ("빈 시간 찾기", "이번 주에 1시간 비는 시간 찾아줘"),
            ("일정 정리", "겹치거나 너무 붙은 일정 알려줘"),
            ("할 일 배치", "미완료 할 일을 빈 시간에 제안해줘")
        ]
        case .todaySummary, .weekReview, .monthReview: [
            ("완료 흐름", "\(context.displayTitle)에서 잘 이어간 작업을 알려줘"),
            ("놓친 작업", "\(context.displayTitle)에서 놓친 작업의 공통점을 찾아줘"),
            ("다음 계획", "\(context.displayTitle) 내용을 바탕으로 다음 계획을 제안해줘")
        ]
        case .settings: [
            ("권한 확인", "Agent가 사용하는 정보를 알려줘"),
            ("요약 설정", "오늘 요약을 간단하게 설정해줘"),
            ("자동화 확인", "반복 일정 실행 전에 무엇을 확인하는지 알려줘")
        ]
        case .today where !hasSchedulesToday: [
            ("일정 만들기", "오늘 오후 2시에 집중 업무 1시간 일정 추가해줘"),
            ("할 일 추가", "오늘 중요한 할 일 1개를 일정으로 만들어줘"),
            ("루틴 시작", "오늘 아침 루틴 30분 일정 만들어줘")
        ]
        case .today: [
            ("일정 추가", "오늘 빈 시간에 집중 일정 1시간 추가해줘"),
            ("오늘 요약", "오늘 일정 핵심만 요약해줘"),
            ("미완료 정리", "남은 할 일을 어떻게 처리할지 알려줘")
        ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("빠른 요청")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoTheme.secondaryInk)

            VStack(spacing: 0) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { index, item in
                    Button { onSelect(item.1) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MemdoTheme.brand)
                                .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.0)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.1)
                                    .font(.caption)
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MemdoTheme.brand)
                        .symbolEffect(.pulse)
                } else if message.isStreaming && message.text.isEmpty {
                    TypingDotsView()
                } else if message.isError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "sparkle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MemdoTheme.brand)
                }
                Text(headerLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }

            // Tool hint
            if let hint = message.toolHint, message.text.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }

            // Main content — markdown-rendered
            if !message.text.isEmpty {
                Group {
                    if let attributed = try? AttributedString(
                        markdown: message.text,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    ) {
                        Text(attributed)
                    } else {
                        Text(message.text)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(message.isError ? .red : MemdoTheme.ink)
                .textSelection(.enabled)
            }

            // Retry
            if message.isError, let onRetry {
                Button(action: onRetry) {
                    Label("다시 시도", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
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
    let onConfirm: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("일정 제안", systemImage: "calendar.badge.plus")
                .font(.caption.weight(.bold))
                .foregroundStyle(MemdoTheme.brand)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MemdoTheme.ink)

                HStack(spacing: 10) {
                    Label(draft.displayDate, systemImage: "calendar")
                    Label(draft.displayTime,
                          systemImage: draft.isTask ? "checkmark.circle" : "clock")
                }
                .font(.caption)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .lineLimit(1)

                if let note = draft.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .lineLimit(2)
                }

                // Reflection result: ProposeScheduleTool already checked this
                // against the real schedule -- surfaced here so approval is an
                // informed choice, not just a rubber stamp.
                if let conflictTitle {
                    Label("같은 시간에 '\(conflictTitle)' 일정이 있어요", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    Label("저장하기", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MemdoTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.accent,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDecline) {
                    Text("취소")
                        .font(.caption.weight(.semibold))
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
