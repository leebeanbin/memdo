import Foundation

/// A model-supplied date token ("today" | "tomorrow" | "yyyy-MM-dd"),
/// resolved and validated in one step. Shared by the on-device Tools
/// (ProposeScheduleTool/FindFreeSlotTool/UpdateScheduleTool) and the cloud
/// staging path in AssistantView.swift, so both trust boundaries reject the
/// same malformed tokens the same way.
enum AgentDateExpression: Equatable {
    case today, tomorrow, yesterday, explicit(Date)

    /// nil means the model produced a token that isn't "today", "tomorrow",
    /// "yesterday", or a real yyyy-MM-dd calendar date -- callers must treat
    /// that as an explicit failure (reject the call, don't stage anything)
    /// rather than falling back to "today". `DateFormatting.posix`'s
    /// `DateFormatter` has `isLenient == false` by default, so an impossible
    /// date like "2026-02-31" already returns nil here without any extra
    /// configuration.
    init?(token: String) {
        switch token {
        case "today": self = .today
        case "tomorrow": self = .tomorrow
        case "yesterday": self = .yesterday
        default:
            guard let date = DateFormatting.posix("yyyy-MM-dd").date(from: token) else { return nil }
            self = .explicit(date)
        }
    }

    /// Total, not failable -- by the time a value exists, `init?` has
    /// already rejected anything unparseable. The `?? .now` fallbacks below
    /// are NOT a model-output boundary: they cover `Calendar.date(byAdding:)`
    /// returning nil, which in practice doesn't happen for a same-day ±1
    /// offset. Model-produced invalid tokens are rejected earlier, at
    /// `init?` -- this distinction (pragmatic internal-arithmetic fallback
    /// vs. never-fallback-on-model-output) is deliberate, not an oversight.
    func resolvedDate(calendar: Calendar = .current) -> Date {
        switch self {
        case .today: calendar.startOfDay(for: .now)
        case .tomorrow: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        case .yesterday: calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now)
        case .explicit(let date): calendar.startOfDay(for: date)
        }
    }
}

/// A model-supplied propose_schedule_update action, validated against the
/// fixed set the backend's proposeScheduleUpdateArgsSchema also enforces.
enum AgentUpdateAction: String {
    case complete, reschedule, delete
}

/// Canonical classification of what an Agent turn actually did. Produced by
/// BOTH runtimes: cloud via classifyAgentIntent(...) below (fed by
/// AgentCloudChatResult's done-payload fields), on-device via the reactive
/// AgentScheduleProposal/AgentScheduleUpdateProposal state at
/// AgentCoordinatorEvent.finished (AssistantView.swift) -- the same state
/// messageList already renders cards from for both runtimes, not a new
/// signal. On-device can only ever produce .answer/.proposeSchedule/
/// .proposeScheduleUpdate (AgentRuntimeKind.onDevice.capabilities has just
/// those 3 tools) -- the other 5 cases are cloud-only by tool availability,
/// not a classification gap. UNSUPPORTED is deliberately NOT a case here:
/// nothing observable at runtime distinguishes "no tool fits, correctly
/// explained" from "a tool was available but the model just answered in
/// text" -- both are the same zero-tool-call, no-clarificationRequest
/// shape. UNSUPPORTED stays an eval-only fixture label (see
/// memdo-backend's eval/grade.ts).
enum AgentIntent: Equatable {
    case answer
    case clarificationRequired
    case proposeSchedule
    case proposeScheduleUpdate
    case proposeRoutineUpdate
    case proposeReviewAction
    case findFreeSlots
    case searchSchedules
}

/// Cloud-path classifier. Priority-ordered: a turn that both searches AND
/// proposes (search first, to check for conflicts) classifies as the
/// proposal, not the search -- the search was supporting work, not the
/// point of the turn. Tool name string literals must match the backend's
/// AGENT_TOOL_NAMES values -- no shared constant across languages, drift
/// caught server-side by buildDonePayload's drift-guard tests, not by a
/// shared type.
func classifyAgentIntent(
    clarificationRequest: CloudClarificationRequestDTO?,
    proposedSchedule: CloudProposedScheduleDTO?,
    proposedScheduleUpdate: CloudProposedScheduleUpdateDTO?,
    proposedRoutineUpdate: CloudProposedRoutineUpdateDTO?,
    proposedReviewAction: CloudProposedReviewActionDTO?,
    toolNames: [String]
) -> AgentIntent {
    if clarificationRequest != nil { return .clarificationRequired }
    if proposedSchedule != nil { return .proposeSchedule }
    if proposedScheduleUpdate != nil { return .proposeScheduleUpdate }
    if proposedRoutineUpdate != nil { return .proposeRoutineUpdate }
    if proposedReviewAction != nil { return .proposeReviewAction }
    if toolNames.contains("find_free_slots") { return .findFreeSlots }
    if toolNames.contains("search_schedules") { return .searchSchedules }
    return .answer
}
