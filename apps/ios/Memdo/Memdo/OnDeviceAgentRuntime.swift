import Foundation
import FoundationModels

/// Owns one FoundationModels session for its whole lifetime -- creation,
/// prewarm, tool registration, and streaming. `tools` is provided once, at
/// init, which is the only place a session (and its tool list) ever gets
/// built. This closes a real bug in the old AssistantView: it had two
/// separate session-creation call sites (one at sheet-appear, one lazily
/// inside sendWithFoundationModels as a fallback) that had drifted apart --
/// the fallback only registered 2 of the 3 tools, silently dropping
/// UpdateScheduleTool for the rest of a session started via that path
/// (which happens on every "새 대화"/reset, since resetConversation()
/// cleared the session but SwiftUI's .task never re-runs for the same view
/// identity). AgentCoordinator now owns *when* a new instance gets built
/// (reuse across sends, discard on reset) -- see AgentCoordinator.swift --
/// so there is exactly one construction site left in the whole app.
@available(iOS 26, *)
final class OnDeviceAgentRuntime: AgentRuntime, @unchecked Sendable {
    let kind: AgentRuntimeKind = .onDevice
    var capabilities: AgentRuntimeCapabilities { kind.capabilities }

    private let session: LanguageModelSession
    /// Shared with every Tool this session was constructed with (see
    /// AssistantView.swift's makeOnDeviceRuntime()) -- send() below is the
    /// only place that ever activates/deactivates it, since it must only
    /// forward to whichever send() call is actually in flight (D4).
    private let activitySink: AgentToolActivitySink

    /// Callers only construct this once on-device availability is already
    /// confirmed (AgentRoutePolicy already decided .onDevice) -- prewarm()
    /// is unconditional here, matching the eager prewarm-at-sheet-appear
    /// timing the current code has today.
    init(tools: [any Tool], instructions: String, activitySink: AgentToolActivitySink) {
        session = LanguageModelSession(tools: tools, instructions: instructions)
        self.activitySink = activitySink
        session.prewarm()
    }

    func send(
        _ request: AgentRuntimeRequest,
        onEvent: @escaping @Sendable (AgentRuntimeEvent) -> Void
    ) async throws {
        activitySink.setActive { capability in onEvent(.toolCallStarted(capability)) }
        defer { activitySink.setActive(nil) }
        let stream = session.streamResponse(to: request.prompt)
        for try await snapshot in stream {
            // FoundationModels' own tool-calling loop has no iteration cap
            // we control (unlike the cloud path's MAX_TOOL_ITERATIONS) --
            // this is the only place a stuck/looping generation can be
            // stopped, via AgentCoordinator cancelling this Task.
            if Task.isCancelled { break }
            onEvent(.textSnapshot(snapshot.content))
        }
    }
}
