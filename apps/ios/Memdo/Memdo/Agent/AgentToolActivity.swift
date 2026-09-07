import Foundation
import os

// Runtime tool-activity signal + mapping (D4), pulled out of
// AgentRuntime.swift/AssistantView.swift (second-pass structural review):
// AgentRuntime.swift is the abstract execution-boundary contract (what a
// runtime IS); everything in this file is D4-specific plumbing for one
// concrete concern -- bridging a real tool-call start/finish into a
// truthful toolHint -- and is independently unit-testable once it isn't
// entangled with either the runtime protocol or SwiftUI view code.

/// Maps a cloud tool's raw name (agent-cloud-contract.ts's AGENT_TOOL_NAMES)
/// to the product-vocabulary capability it represents, for the toolHint
/// pipeline (D4) -- NOT used for AgentIntent classification, which has its
/// own separate mapping in AgentIntent.swift. Tool name string literals
/// must match the backend's AGENT_TOOL_NAMES values; there's no shared type
/// across languages, same as AgentIntent.swift's classifier. An unmapped or
/// unrecognized name (e.g. request_clarification, whose own response text
/// IS the user-facing signal -- no separate mid-turn hint makes sense for
/// it) returns nil rather than guessing, so it simply shows no hint instead
/// of a wrong one.
func cloudToolCapability(forRawName name: String) -> AgentCapability? {
    switch name {
    case "search_schedules": return .scheduleSearch
    case "find_free_slots": return .freeSlotSearch
    case "propose_schedule": return .proposeSchedule
    case "propose_schedule_update": return .proposeScheduleUpdate
    case "get_day_context": return .dayContext
    case "get_routine_preferences": return .routinePreferences
    case "propose_routine_update": return .proposeRoutineUpdate
    case "get_review_history": return .reviewHistory
    case "propose_review_actions": return .proposeReviewActions
    default: return nil
    }
}

/// One truthful wording per capability GROUP, not per raw tool name (D4)
/// -- read-only context lookups (get_day_context/get_routine_preferences/
/// get_review_history) don't need 3 separate phrasings the user has no way
/// to tell apart in practice, and all 4 propose_* tools genuinely are
/// "preparing a change" from the user's point of view. Every wording here
/// corresponds to a real .toolCallStarted event; nothing here is shown
/// speculatively. A free function (not a View method) specifically so it's
/// unit-testable without driving AssistantView.
func toolHintText(for capability: AgentCapability) -> String {
    switch capability {
    case .scheduleSearch:
        "기존 일정 찾는 중..."
    case .freeSlotSearch:
        "빈 시간 계산하는 중..."
    case .dayContext, .routinePreferences, .reviewHistory:
        "일정 확인하는 중..."
    case .proposeSchedule, .proposeScheduleUpdate, .proposeRoutineUpdate, .proposeReviewActions:
        "변경안 준비하는 중..."
    }
}

/// Bridges an on-device Tool's call-time activity to whichever
/// AgentRuntimeEvent sink is active for the send() currently in flight
/// (D4). Tools are constructed once per conversation and reused across many
/// send() calls (see AssistantView.swift's makeOnDeviceRuntime() doc
/// comment), but `onEvent` is only valid for whichever send() is currently
/// running -- so this is a swappable indirection OnDeviceAgentRuntime.send()
/// sets before streaming and clears after, not a closure captured once at
/// Tool-construction time. OSAllocatedUnfairLock rather than @MainActor:
/// Tool.call(arguments:) is not actor-isolated, and report(_:) must be
/// callable from whatever context FoundationModels invokes a Tool on.
///
/// Handler type is `(AgentRuntimeEvent) -> Void`, matching `onEvent`
/// exactly -- OnDeviceAgentRuntime.send() activates this sink with its own
/// `onEvent` directly (`activitySink.setActive(onEvent)`), no adapting
/// needed on either side.
final class AgentToolActivitySink: @unchecked Sendable {
    private let handler = OSAllocatedUnfairLock<(@Sendable (AgentRuntimeEvent) -> Void)?>(initialState: nil)

    func setActive(_ newHandler: (@Sendable (AgentRuntimeEvent) -> Void)?) {
        handler.withLock { $0 = newHandler }
    }

    /// Called directly by a Tool as literally the first statement of its
    /// call(arguments:) -- a real "this tool call just started" signal, not
    /// inferred from its result. A no-op if no send() is currently active
    /// (there always should be one while a Tool is executing, but this
    /// stays silent rather than crashing if that invariant is ever broken).
    func reportStarted(_ capability: AgentCapability) {
        handler.withLock { $0 }?(.toolCallStarted(capability))
    }

    /// Called directly by a Tool via `defer`, guaranteeing this fires
    /// whether call(arguments:) returns normally or throws (D4 second-pass
    /// review) -- see AgentRuntimeEvent.toolCallFinished's doc comment.
    func reportFinished(_ capability: AgentCapability) {
        handler.withLock { $0 }?(.toolCallFinished(capability))
    }
}
