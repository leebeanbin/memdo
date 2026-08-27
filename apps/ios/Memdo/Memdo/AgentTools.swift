import Foundation
import FoundationModels

// MARK: - Cloud conversation history

/// Turns already-settled messages into the flat, provider-neutral turn
/// history AgentCoordinator/AgentRuntime deal in, excluding the current
/// turn.
///
/// Precondition: `messages.last` is the current turn, already about to be
/// sent separately as the request's `prompt` -- `dispatchToModel(_:)`
/// guarantees this by computing history before appending the turn's own
/// placeholder. Including it here as well would send the same turn twice:
/// once as the trailing item of `history`, once again as the prompt.
func agentConversationHistory(from messages: [AgentMessage]) -> [AgentConversationTurn] {
    messages.dropLast()
        .filter { !$0.isStreaming && !$0.isError }
        .map { AgentConversationTurn(role: $0.role == .user ? .user : .assistant, content: $0.text) }
}

/// Cloud-specific DTO shape, derived from the same provider-neutral history
/// above -- kept as its own entry point since existing tests exercise it
/// directly.
func agentCloudHistory(from messages: [AgentMessage]) -> [AgentChatTurnDTO] {
    agentChatTurnDTOs(from: agentConversationHistory(from: messages))
}

// MARK: - Live schedule-state providers (Epic D-2)
//
// Free functions rather than AssistantView-private methods so the closures
// passed into on-device Tools (below) can capture just `scheduleStore` --
// a stable, @MainActor-isolated reference type -- instead of the whole
// AgentSheet View struct.

@MainActor
func existingItemsSnapshot(_ scheduleStore: ScheduleStore) -> [ConflictService.ExistingItem] {
    scheduleStore.schedules.map {
        .init(id: $0.id.uuidString, title: $0.title, startAt: $0.startAt, endAt: $0.endAt)
    }
}

@available(iOS 26, *)
@MainActor
func scheduleIntervalSnapshot(_ scheduleStore: ScheduleStore) -> [FindFreeSlotTool.ScheduleInterval] {
    scheduleStore.schedules.map {
        .init(scheduledDate: $0.scheduledDate, startAt: $0.startAt, endAt: $0.endAt)
    }
}

// MARK: - Schedule Proposal (Tool result)

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
        // By the time a token reaches display, it was already validated via
        // AgentDateExpression(token:) at whichever staging boundary produced
        // it (ProposeScheduleTool/UpdateScheduleTool's call(arguments:), or
        // AssistantView's cloud-response staging) -- this branch should only
        // ever see an already-valid explicit yyyy-MM-dd. Falls back to the
        // raw token text, not "오늘", if that invariant is ever violated, so
        // a bug here is visible instead of silently mislabeled as today.
        guard let expr = AgentDateExpression(token: token) else { return token }
        return DateFormatting.korean("M월 d일").string(from: expr.resolvedDate())
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

    /// Same "already validated by the time this exists" invariant as
    /// displayAgentDateToken -- ProposeScheduleTool.call(arguments:) and
    /// AssistantView's cloud-response staging both reject an unparseable
    /// date before a draft with that dateString is ever created.
    func scheduledDate() -> Date {
        AgentDateExpression(token: dateString)?.resolvedDate() ?? Calendar.current.startOfDay(for: .now)
    }

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
    /// Conflict snapshot as of staging time (on-device Tool call, or cloud
    /// response ingestion) -- ConflictService.conflict(...) recomputed
    /// locally against scheduleStore.schedules in both cases (Issue C-04),
    /// not trusted from the server's own conflictTitle. Confirm-time
    /// revalidates this against a fresh recomputation before mutating; see
    /// conflictRevalidationDecision(staged:fresh:).
    var conflict: AgentConflictSnapshot?
    /// True when the conflict check itself couldn't be verified server-side
    /// (see CloudProposedScheduleDTO.conflictCheckFailed) -- shown as its own
    /// warning rather than silently treated as "no conflict." Server-only
    /// signal (a local recomputation can't fail the way a DB fetch can), so
    /// it stays independent of `conflict`.
    var conflictCheckFailed: Bool = false
    /// Bumped every time propose(_:) stages something new -- lets callers
    /// ask "did a new proposal get staged during THIS turn" instead of "is
    /// something staged right now" (draft != nil stays true for an old,
    /// not-yet-approved-or-declined proposal across many later turns, which
    /// would otherwise misattribute a later turn's intent -- see
    /// AssistantView.handleCoordinatorEvent's .finished case). Monotonic:
    /// clear() does NOT reset it -- clearing means "the user resolved this
    /// proposal," not "this proposal never happened."
    private(set) var revision = 0
    func propose(_ d: ProposedScheduleDraft, conflict: AgentConflictSnapshot? = nil, conflictCheckFailed: Bool = false) {
        draft = d
        self.conflict = conflict
        self.conflictCheckFailed = conflictCheckFailed
        revision += 1
    }
    func clear() { draft = nil; conflict = nil; conflictCheckFailed = false }
}

/// Pending state for an Agent proposal to complete, move, or delete an
/// EXISTING item (propose_schedule_update), mirroring AgentScheduleProposal's
/// shape for creates. `id` is the real todos.id (on-device: resolved by
/// UpdateScheduleTool.bestMatch(for:); cloud: echoed back from
/// search_schedules), not a client-generated value.
@MainActor
@Observable
final class AgentScheduleUpdateProposal {
    var id: String?
    var action: String?           // "complete" | "reschedule" | "delete"
    var title: String?
    var dateString: String?       // reschedule only
    var startTimeString: String?  // reschedule only
    var endTimeString: String?    // reschedule only
    /// Same staging-time-local-recomputation contract as
    /// AgentScheduleProposal.conflict -- see that doc comment.
    var conflict: AgentConflictSnapshot?
    var conflictCheckFailed: Bool = false

    var isPending: Bool { id != nil }

    /// Same monotonic-staging-generation contract as
    /// AgentScheduleProposal.revision -- see that doc comment.
    private(set) var revision = 0

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
        conflict: AgentConflictSnapshot?,
        conflictCheckFailed: Bool
    ) {
        self.id = id
        self.action = action
        self.title = title
        self.dateString = dateString
        self.startTimeString = startTimeString
        self.endTimeString = endTimeString
        self.conflict = conflict
        self.conflictCheckFailed = conflictCheckFailed
        revision += 1
    }

    func clear() {
        id = nil
        action = nil
        title = nil
        dateString = nil
        startTimeString = nil
        endTimeString = nil
        conflict = nil
        conflictCheckFailed = false
    }
}

/// Pending state for an Agent proposal to change routine settings
/// (propose_routine_update) -- cloud-only (see AgentRuntimeKind.capabilities),
/// so this is only ever staged from AssistantView.ingestCloudResult, not an
/// on-device Tool. No conflict concept, unlike the schedule proposals --
/// routine settings don't collide with each other the way time ranges do.
@MainActor
@Observable
final class AgentRoutineUpdateProposal {
    var draft: CloudProposedRoutineUpdateDTO?
    var isPending: Bool { draft != nil }
    func propose(_ d: CloudProposedRoutineUpdateDTO) { draft = d }
    func clear() { draft = nil }
}

/// Pending state for an Agent proposal to write/update a day's reflection
/// (propose_review_actions) -- cloud-only, same reasoning as
/// AgentRoutineUpdateProposal above.
@MainActor
@Observable
final class AgentReviewActionProposal {
    var draft: CloudProposedReviewActionDTO?
    var isPending: Bool { draft != nil }
    func propose(_ d: CloudProposedReviewActionDTO) { draft = d }
    func clear() { draft = nil }
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

    let proposal: AgentScheduleProposal
    /// Read at call time, not captured once at Tool construction -- so a
    /// session reused across several turns always stages against the
    /// current schedule instead of whatever existed when the session was
    /// first created (Epic D-2; Epic C's confirm-time revalidation remains
    /// the actual safety net regardless).
    let existingProvider: @MainActor @Sendable () -> [ConflictService.ExistingItem]
    /// Reports this call's start to AgentToolActivitySink for the toolHint
    /// pipeline (D4) -- see that type's doc comment. Defaults to a no-op so
    /// existing construction sites (tests) don't need updating.
    var onStart: @Sendable (AgentCapability) -> Void = { _ in }

    func call(arguments: Arguments) async throws -> String {
        onStart(.proposeSchedule)
        let result = stageScheduleProposal(
            title: arguments.title,
            date: arguments.date,
            startTime: arguments.startTime,
            endTime: arguments.endTime,
            isTask: arguments.isTask,
            note: arguments.note,
            existing: await existingProvider()
        )
        switch result {
        case .invalidDate:
            return "날짜를 이해하지 못했어요. 다시 말씀해 주세요."
        case .staged(let draft, let conflict, let conflictCheckFailed):
            await proposal.propose(draft, conflict: conflict, conflictCheckFailed: conflictCheckFailed)
            guard let conflict else {
                return "'\(draft.title)' 일정을 제안했습니다."
            }
            return "'\(draft.title)' 일정을 제안했습니다. 주의: 같은 시간에 이미 '\(conflict.title)' 일정이 있어요."
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
    let description = "Finds available free time in the user's calendar. Two modes based on whether durationMinutes is given: a plain availability question ('언제 비어 있어?') with no explicit numeric duration returns the full free window; a request with an explicit numeric duration ('1시간 찾아줘') returns one candidate slot of that length. An activity name ALONE ('운동할 시간 찾아줘') is NOT a duration -- if the user names an activity but never states how long, ask them in plain text how much time they need instead of guessing or calling this tool with a made-up value. Call this whenever the user asks about free time, an open slot, or where to fit something — never guess availability from context alone."

    @Generable
    struct Arguments: Sendable {
        @Guide(description: "Date scope — one of: 'today', 'tomorrow', 'this_week', or a specific yyyy-MM-dd")
        let scope: String
        // Optional, not defaulted to 30/60 anywhere -- absence has its own
        // precise meaning (availability query), not "duration unspecified,
        // guess one." See call(arguments:)'s branch below. Found during
        // founder dogfooding: an empty day answered a plain "when am I
        // free" question with a single arbitrary duration-sized slot
        // instead of the whole open window, because this used to be a
        // required Int the model had to invent a value for. A second bug
        // in the same family (also found during dogfooding): the original
        // fix's wording still let a bare activity name ("운동", "공부")
        // count as justification for inventing a number -- it must not.
        // On-device has no request_clarification tool (a known, separate
        // gap), so the fallback here is a plain-text question, not a tool
        // call.
        @Guide(description: "Free-slot length in minutes (e.g. 30, 60, 90), ONLY when the user states an explicit numeric duration. Omit entirely for a plain availability question -- omitting returns the full free window, never a guessed duration. An activity name by itself (e.g. \"운동\") is NOT evidence for any particular number here -- if a duration is genuinely needed but never stated, ask the user in plain text instead of inventing one.")
        let durationMinutes: Int?
        @Guide(description: "Earliest start time HH:mm, e.g. '09:00'. Empty string = no preference.")
        let windowStart: String
        @Guide(description: "Latest end time HH:mm, e.g. '21:00'. Empty string = no preference.")
        let windowEnd: String
    }

    /// Read at call time, not captured once at Tool construction -- see
    /// ProposeScheduleTool.existingProvider's doc comment.
    let snapshotProvider: @MainActor @Sendable () -> [ScheduleInterval]
    /// See ProposeScheduleTool.onStart's doc comment.
    var onStart: @Sendable (AgentCapability) -> Void = { _ in }

    /// Same 15...480 minute bound the backend's findFreeSlotsArgsSchema
    /// enforces (Issue A-04/B-04) -- clamping a model-supplied value that's
    /// too small/large would silently answer a different question than
    /// asked, so this rejects instead of clamping.
    static let allowedDurationMinutes = 15...480

    func call(arguments: Arguments) async throws -> String {
        onStart(.freeSlotSearch)
        guard let dates = validScopeDates(arguments.scope) else {
            return "요청한 기간을 이해하지 못했어요."
        }

        guard let durationMinutes = arguments.durationMinutes else {
            return await availabilityAnswer(dates: dates, windowStart: arguments.windowStart, windowEnd: arguments.windowEnd)
        }
        guard Self.allowedDurationMinutes.contains(durationMinutes) else {
            return "요청한 시간이 너무 짧거나 길어요. 15분에서 8시간(480분) 사이로 다시 말씀해 주세요."
        }
        let duration = TimeInterval(durationMinutes * 60)
        let snapshot = await snapshotProvider()

        var lines: [String] = []
        for date in dates {
            let busyOnDay = snapshot.filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) }
            let (start, end) = window(on: date, wStart: arguments.windowStart, wEnd: arguments.windowEnd)
            let slots = FreeSlotService.freeSlots(
                busy: busyRanges(busyOnDay), windowStart: start, windowEnd: end, duration: duration
            )
            guard !slots.isEmpty else { continue }
            lines.append("\(dateLabel(date)): \(slots.map(formatInterval).joined(separator: ", "))")
        }

        return lines.isEmpty ? "요청한 조건에 맞는 빈 시간을 찾지 못했어요." : lines.joined(separator: "\n")
    }

    /// Absence of durationMinutes means "how free am I", not "duration
    /// unspecified, guess one" -- reports the full free extent of the
    /// window, not a duration-sized slice of it. Found during founder
    /// dogfooding: this is the actual fix for an empty day answering
    /// "1 hour free" to a plain availability question.
    private func availabilityAnswer(dates: [Date], windowStart wStart: String, windowEnd wEnd: String) async -> String {
        let snapshot = await snapshotProvider()

        var lines: [String] = []
        for date in dates {
            let busyOnDay = snapshot.filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) }
            let (start, end) = window(on: date, wStart: wStart, wEnd: wEnd)
            let extents = FreeSlotService.fullFreeExtents(busy: busyRanges(busyOnDay), windowStart: start, windowEnd: end)
            guard !extents.isEmpty else { continue }
            if extents.count == 1, extents[0].start == start, extents[0].end == end {
                // Deliberately no "등록된 일정이 없어서" causal claim --
                // busyRanges(_:) (below) only looks at timed items, so an
                // untimed task can still exist on this date even when the
                // whole timed window is free. Stating only the computed
                // fact (the window itself) stays true regardless.
                lines.append("\(dateLabel(date)): \(formatInterval(extents[0])) 전체가 비어 있어요.")
            } else {
                lines.append("\(dateLabel(date)): \(extents.map(formatInterval).joined(separator: ", ")) 비어 있어요.")
            }
        }

        return lines.isEmpty ? "요청한 기간에는 비어 있는 시간이 없어요." : lines.joined(separator: "\n")
    }

    /// nil means the model produced a scope this tool doesn't understand --
    /// callers must reject the call rather than defaulting to today.
    private func validScopeDates(_ scope: String) -> [Date]? {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: .now)
        switch scope {
        case "today":     return [today]
        case "tomorrow":  return [cal.date(byAdding: .day, value: 1, to: today) ?? today]
        case "this_week": return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        default:
            guard let expr = AgentDateExpression(token: scope) else { return nil }
            return [expr.resolvedDate(calendar: cal)]
        }
    }

    /// The product-defined default planning window (08:00-22:00) when the
    /// model didn't supply an explicit windowStart/windowEnd -- shared by
    /// both the duration-candidate path and the availability path so they
    /// never silently disagree on what "the whole day" means.
    private func window(on date: Date, wStart: String, wEnd: String) -> (Date, Date) {
        let cal   = Calendar.current
        let start = timeFrom(wStart, on: date) ?? cal.date(bySettingHour: 8,  minute: 0, second: 0, of: date)!
        let end   = timeFrom(wEnd,   on: date) ?? cal.date(bySettingHour: 22, minute: 0, second: 0, of: date)!
        return (start, end)
    }

    private func busyRanges(_ busy: [ScheduleInterval]) -> [AgentTimeRange] {
        busy.compactMap { s in
            guard let s1 = s.startAt, let e1 = s.endAt else { return nil }
            return AgentTimeRange(start: s1, end: e1)
        }
    }

    private func timeFrom(_ hhmm: String, on date: Date) -> Date? {
        guard !hhmm.isEmpty else { return nil }
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }

    private func formatInterval(_ interval: AgentTimeRange) -> String {
        let f = DateFormatting.korean("H:mm")
        return "\(f.string(from: interval.start))–\(f.string(from: interval.end))"
    }

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)    { return "오늘" }
        if cal.isDateInTomorrow(date) { return "내일" }
        let f = DateFormatting.korean("M월 d일(E)")
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
    /// Read at call time, not captured once at Tool construction -- see
    /// ProposeScheduleTool.existingProvider's doc comment.
    let existingProvider: @MainActor @Sendable () -> [ConflictService.ExistingItem]
    /// See ProposeScheduleTool.onStart's doc comment.
    var onStart: @Sendable (AgentCapability) -> Void = { _ in }

    func call(arguments: Arguments) async throws -> String {
        onStart(.proposeScheduleUpdate)
        guard let action = AgentUpdateAction(rawValue: arguments.action) else {
            return "요청하신 작업을 이해하지 못했어요."
        }
        let existing = await existingProvider()
        guard let match = bestMatch(for: arguments.title, in: existing) else {
            return "'\(arguments.title)'과(와) 일치하는 일정을 찾지 못했어요."
        }

        let result = stageScheduleUpdate(
            id: match.id,
            title: match.title,
            action: action,
            dateString: arguments.date.isEmpty ? nil : arguments.date,
            startTimeString: arguments.startTime.isEmpty ? nil : arguments.startTime,
            endTimeString: arguments.endTime.isEmpty ? nil : arguments.endTime,
            existing: existing
        )
        switch result {
        case .invalidDate:
            return "옮길 날짜를 이해하지 못했어요. 다시 말씀해 주세요."
        case .staged(let id, let action, let title, let dateString, let startTimeString, let endTimeString, let conflict, let conflictCheckFailed):
            await proposal.propose(
                id: id, action: action.rawValue, title: title,
                dateString: dateString, startTimeString: startTimeString, endTimeString: endTimeString,
                conflict: conflict, conflictCheckFailed: conflictCheckFailed
            )
            guard let conflict else {
                return "'\(title)' 항목에 대한 변경을 제안했습니다."
            }
            return "'\(title)' 항목에 대한 변경을 제안했습니다. 주의: 같은 시간에 이미 '\(conflict.title)' 일정이 있어요."
        }
    }

    private func bestMatch(for title: String, in existing: [ConflictService.ExistingItem]) -> ConflictService.ExistingItem? {
        let needle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let exact = existing.first(where: { $0.title == needle }) { return exact }
        return existing.first {
            $0.title.localizedCaseInsensitiveContains(needle) || needle.localizedCaseInsensitiveContains($0.title)
        }
    }
}
