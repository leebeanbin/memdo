import Foundation

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
    /// The same tool call genuinely just finished -- fired the instant the
    /// handler resolves (success or failure), not left implicit (D4
    /// second-pass review: toolCallStarted alone left a UI hint showing
    /// "executing" through the whole gap after the handler had already
    /// finished, until the model's next visible token -- a fake progress
    /// state in substance even though no such string was ever written).
    /// Cloud: agent-cloud-chat's `toolCallFinished` stream line, sent
    /// immediately after dispatchToolCall resolves. On-device: a Tool's
    /// `defer` block, guaranteeing this fires even if call(arguments:)
    /// throws.
    case toolCallFinished(AgentCapability)
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
