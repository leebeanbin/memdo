import Foundation
import os

/// Which execution path an Agent turn runs on. Provider-neutral by design --
/// no model ID or FoundationModels/OpenRouter-specific type belongs here or
/// anywhere in AgentCapability/AgentRoutePolicy.
enum AgentRuntimeKind: Equatable, Sendable {
    case onDevice
    case cloud
}

/// Product/domain vocabulary for what an Agent turn can do -- not a 1:1 tool
/// name mapping, so a future tool rename doesn't ripple into routing/UI code
/// that only cares about capability.
enum AgentCapability: Hashable, Sendable {
    case scheduleSearch
    case freeSlotSearch

    case proposeSchedule
    case proposeScheduleUpdate

    case dayContext
    case routinePreferences
    case reviewHistory

    case proposeRoutineUpdate
    case proposeReviewActions
}

struct AgentRuntimeCapabilities: Equatable, Sendable {
    let supported: Set<AgentCapability>

    func supports(_ capability: AgentCapability) -> Bool {
        supported.contains(capability)
    }
}

/// Minimal execution boundary -- deliberately not a "do everything" adapter
/// protocol. Proposal staging (propose_schedule/update) is NOT represented
/// here: on-device Tools mutate a proposal reference directly as a side
/// effect while the model is still streaming, and cloud staging happens via
/// CloudAgentRuntime's separately-injected onResult completion handler
/// (see CloudAgentRuntime) -- unifying those into one shared event would
/// require redesigning the on-device Tool architecture, out of scope for
/// this slice.
protocol AgentRuntime: AnyObject, Sendable {
    var kind: AgentRuntimeKind { get }
    var capabilities: AgentRuntimeCapabilities { get }

    /// Runs one turn to completion. Only returns once every onEvent call for
    /// this turn has happened AND (for a runtime with one, i.e. cloud) its
    /// own result-completion handling has finished -- callers can rely on
    /// "send() returned" meaning "everything about this turn already
    /// happened," not just "streaming stopped."
    func send(
        _ request: AgentRuntimeRequest,
        onEvent: @escaping @Sendable (AgentRuntimeEvent) -> Void
    ) async throws
}

struct AgentRuntimeRequest: Sendable {
    let prompt: String
    /// Ignored by OnDeviceAgentRuntime -- LanguageModelSession keeps its own
    /// multi-turn history internally, which is the whole point of reusing
    /// one session across a conversation. Only CloudAgentRuntime consumes
    /// this, since agent-cloud-chat is stateless per call and needs the
    /// full turn history sent explicitly every time.
    let history: [AgentConversationTurn]
}

struct AgentConversationTurn: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    let role: Role
    let content: String
}

/// The full assistant text so far, not an incremental delta. On-device
/// (LanguageModelSession.streamResponse) already yields cumulative
/// snapshots; CloudAgentRuntime accumulates its own incremental chunks into
/// the same shape internally, so callers always just do
/// `messages[i].text = text` regardless of which runtime produced it.
enum AgentRuntimeEvent: Sendable {
    case textSnapshot(String)
    /// A tool call genuinely just started -- fired the instant execution
    /// begins, not inferred after the fact from a result (D4). Cloud:
    /// forwarded from agent-cloud-chat's `toolCallStarted` stream line,
    /// sent server-side before the (possibly slow) handler runs. On-device:
    /// forwarded from a Tool's call(arguments:) via AgentToolActivitySink
    /// (below), as literally its first statement. Both are real signals;
    /// neither is inferred or guessed.
    case toolCallStarted(AgentCapability)
}

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
final class AgentToolActivitySink: @unchecked Sendable {
    private let handler = OSAllocatedUnfairLock<(@Sendable (AgentCapability) -> Void)?>(initialState: nil)

    func setActive(_ newHandler: (@Sendable (AgentCapability) -> Void)?) {
        handler.withLock { $0 = newHandler }
    }

    /// Called directly by a Tool as literally the first statement of its
    /// call(arguments:) -- a real "this tool call just started" signal, not
    /// inferred from its result. A no-op if no send() is currently active
    /// (there always should be one while a Tool is executing, but this
    /// stays silent rather than crashing if that invariant is ever broken).
    func report(_ capability: AgentCapability) {
        handler.withLock { $0 }?(capability)
    }
}

extension AgentRuntimeKind {
    /// Mirrors docs/20-ai-agent-architecture.md §5's tool grouping -- the
    /// on-device set is 3 FoundationModels Tools (AgentTools.swift), the
    /// cloud set is the 9 entries in agent-cloud-contract.ts's toolHandlers.
    var capabilities: AgentRuntimeCapabilities {
        switch self {
        case .onDevice:
            .init(supported: [
                .freeSlotSearch,
                .proposeSchedule,
                .proposeScheduleUpdate,
            ])

        case .cloud:
            .init(supported: [
                .scheduleSearch,
                .freeSlotSearch,
                .proposeSchedule,
                .proposeScheduleUpdate,
                .dayContext,
                .routinePreferences,
                .reviewHistory,
                .proposeRoutineUpdate,
                .proposeReviewActions,
            ])
        }
    }
}
