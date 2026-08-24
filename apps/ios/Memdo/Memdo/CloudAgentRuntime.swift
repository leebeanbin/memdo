import Foundation

/// Maps the provider-neutral turn history onto the backend's DTO shape --
/// the one piece of translation logic CloudAgentRuntime does, pulled out so
/// it's testable without a live network call.
func agentChatTurnDTOs(from history: [AgentConversationTurn]) -> [AgentChatTurnDTO] {
    history.map { AgentChatTurnDTO(role: $0.role == .user ? "user" : "assistant", content: $0.content) }
}

/// Owns the cloud-specific request/response shape (agent-cloud-chat) and
/// model preference. No new networking layer -- delegates to
/// ScheduleStore.agentCloudChat, the same call AssistantView makes today.
final class CloudAgentRuntime: AgentRuntime, @unchecked Sendable {
    let kind: AgentRuntimeKind = .cloud
    var capabilities: AgentRuntimeCapabilities { kind.capabilities }

    private let scheduleStore: ScheduleStore
    /// Invoked once send()'s underlying agentCloudChat call returns, with
    /// the full result (proposedSchedule/proposedScheduleUpdate included).
    /// This runtime doesn't interpret the result itself -- conflict
    /// recomputation and draft construction stay in the caller's existing
    /// ingestion logic (today's sendWithCloudAgent body), matching how
    /// on-device Tools stage their own proposal directly rather than going
    /// through a shared event type. nil is valid for callers (tests) that
    /// don't care about staging.
    private let onResult: (@MainActor (AgentCloudChatResult) -> Void)?

    init(scheduleStore: ScheduleStore, onResult: (@MainActor (AgentCloudChatResult) -> Void)? = nil) {
        self.scheduleStore = scheduleStore
        self.onResult = onResult
    }

    /// Returns only after streaming AND (if provided) onResult have both
    /// run, per the AgentRuntime.send() contract -- agentCloudChat's own
    /// await already sequences it this way; nothing extra is needed here.
    func send(
        _ request: AgentRuntimeRequest,
        onEvent: @escaping @Sendable (AgentRuntimeEvent) -> Void
    ) async throws {
        let history = agentChatTurnDTOs(from: request.history)
        var accumulated = ""
        let result = try await scheduleStore.agentCloudChat(
            message: request.prompt,
            history: history,
            model: CloudAgentModelPreference.selected
        ) { delta in
            accumulated += delta
            onEvent(.textSnapshot(accumulated))
        }
        if let onResult {
            await onResult(result)
        }
    }
}
