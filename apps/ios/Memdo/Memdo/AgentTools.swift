import Foundation
import FoundationModels

// MARK: - Cloud conversation history

/// Turns already-settled messages into the flat history the stateless cloud
/// endpoint expects, excluding the current turn.
///
/// Precondition: `messages.last` is the current turn, already about to be
/// sent separately as the request's `message` field -- `send()`/`retry()`
/// both guarantee this by appending (or leaving) the current user turn as
/// the last element before dispatching. Including it here as well would
/// send the same turn twice: once as the trailing item of `history`, once
/// again as `message`.
func agentCloudHistory(from messages: [AgentMessage]) -> [AgentChatTurnDTO] {
    messages.dropLast()
        .filter { !$0.isStreaming && !$0.isError }
        .map { AgentChatTurnDTO(role: $0.role == .user ? "user" : "assistant", content: $0.text) }
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
        // Reject before staging anything -- an unparseable date must never
        // silently become "today" (Issue A-04).
        guard AgentDateExpression(token: arguments.date) != nil else {
            return "날짜를 이해하지 못했어요. 다시 말씀해 주세요."
        }
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

    /// Same 15...480 minute bound the backend's findFreeSlotsArgsSchema
    /// enforces (Issue A-04/B-04) -- clamping a model-supplied value that's
    /// too small/large would silently answer a different question than
    /// asked, so this rejects instead of clamping.
    static let allowedDurationMinutes = 15...480

    func call(arguments: Arguments) async throws -> String {
        guard let dates = validScopeDates(arguments.scope) else {
            return "요청한 기간을 이해하지 못했어요."
        }
        guard Self.allowedDurationMinutes.contains(arguments.durationMinutes) else {
            return "요청한 시간이 너무 짧거나 길어요. 15분에서 8시간(480분) 사이로 다시 말씀해 주세요."
        }
        let duration = TimeInterval(arguments.durationMinutes * 60)

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
        let f = DateFormatting.korean("H:mm")
        let endTime  = interval.start.addingTimeInterval(interval.duration)
        return "\(f.string(from: interval.start))–\(f.string(from: endTime))"
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
        guard let action = AgentUpdateAction(rawValue: arguments.action) else {
            return "요청하신 작업을 이해하지 못했어요."
        }
        guard let match = bestMatch(for: arguments.title) else {
            return "'\(arguments.title)'과(와) 일치하는 일정을 찾지 못했어요."
        }

        // Reschedule requires a real target date -- an empty or unparseable
        // one must be rejected outright, not silently treated as today
        // (Issue A-04). complete/delete never carry a date at all.
        var rescheduleDay: Date?
        if action == .reschedule {
            guard !arguments.date.isEmpty, let expr = AgentDateExpression(token: arguments.date) else {
                return "옮길 날짜를 이해하지 못했어요. 다시 말씀해 주세요."
            }
            rescheduleDay = expr.resolvedDate()
        }

        var conflict: ExistingItem?
        if let day = rescheduleDay, !arguments.startTime.isEmpty {
            if let start = parseAgentTime(arguments.startTime, on: day) {
                let end = arguments.endTime.isEmpty
                    ? start.addingTimeInterval(3_600)
                    : (parseAgentTime(arguments.endTime, on: day) ?? start.addingTimeInterval(3_600))
                conflict = conflictingItem(excluding: match.id, start: start, end: end)
            }
        }

        await proposal.propose(
            id: match.id,
            action: action.rawValue,
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
