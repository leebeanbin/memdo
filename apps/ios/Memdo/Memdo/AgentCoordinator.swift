import Foundation

/// Normalized outcomes AgentCoordinator emits -- routing, runtime
/// construction, and cancellation never surface past this boundary.
/// AssistantView only reacts to these four cases.
enum AgentCoordinatorEvent: Equatable, Sendable {
    case started(AgentRuntimeKind)
    case textSnapshot(String)
    case finished
    case failed(AgentExecutionFailure)
}

/// Deliberately minimal -- domain/model-semantic failures (invalid date,
/// schedule conflict, unsupported action) are not execution failures and
/// don't belong here; those already surface through the normal
/// proposal/tool-result text. No `.cancelled` case: cancellation only ever
/// happens because a newer send() superseded this one or resetConversation()
/// was called, both internally triggered by AgentCoordinator itself -- never
/// a user-visible failure, so it's simply never emitted (see send()'s
/// CancellationError handling below).
enum AgentExecutionFailure: Equatable, Sendable {
    case cloudConnectionRequired
    case runtimeFailure
}

/// Owns Agent execution lifecycle: which runtime a turn goes to
/// (AgentRoutePolicy, the only place that's decided), the in-flight Task and
/// its cancellation, and on-device session reuse/reset. Does NOT own
/// anything about proposals, conflicts, or free slots -- those stay in
/// AgentDomainServices.swift and the caller's own ingestion logic.
@MainActor
final class AgentCoordinator {
    private var activeTask: Task<Void, Never>?
    private var cachedOnDeviceRuntime: AgentRuntime?
    private let onDeviceRuntimeFactory: (() -> AgentRuntime)?
    private let cloudRuntime: AgentRuntime

    /// onDeviceRuntimeFactory is nil on OS versions where on-device is never
    /// available at all (pre-iOS 26) -- callers still route to cloud in that
    /// case, this just means there's nothing to prewarm/cache.
    init(onDeviceRuntimeFactory: (() -> AgentRuntime)?, cloudRuntime: AgentRuntime) {
        self.onDeviceRuntimeFactory = onDeviceRuntimeFactory
        self.cloudRuntime = cloudRuntime
    }

    /// Prewarms on-device as early as possible -- same timing as the old
    /// AssistantView's eager session-at-sheet-appear (`.task`). A no-op if
    /// a runtime is already cached or no factory was given. Returns true
    /// only when this call actually built a new runtime (as opposed to
    /// reusing a cached one or having no factory to call) -- the caller
    /// uses this to decide whether to show the "새 세션이 시작됐어요" banner,
    /// same condition the old `if typedSession == nil { ... }` check used.
    @discardableResult
    func prewarmOnDevice() -> Bool {
        let hadCachedRuntime = cachedOnDeviceRuntime != nil
        let runtime = onDeviceRuntime(creatingIfNeeded: true)
        return !hadCachedRuntime && runtime != nil
    }

    private func onDeviceRuntime(creatingIfNeeded: Bool) -> AgentRuntime? {
        if let cachedOnDeviceRuntime { return cachedOnDeviceRuntime }
        guard creatingIfNeeded, let onDeviceRuntimeFactory else { return nil }
        let created = onDeviceRuntimeFactory()
        cachedOnDeviceRuntime = created
        return created
    }

    /// Cancels whatever's in flight. Safe to call even with nothing running.
    func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    /// Discards the cached on-device runtime (and, with it, its
    /// LanguageModelSession/conversation context) so the next on-device send
    /// builds a fresh one instead of continuing the old session. Callers
    /// call cancel() first (resetConversation() does both, in that order).
    func resetRuntime() {
        cachedOnDeviceRuntime = nil
    }

    /// Cancels any in-flight turn, decides on-device vs cloud via
    /// AgentRoutePolicy, and runs the new turn. onEvent may be called
    /// multiple times (.started once, then any number of .textSnapshot,
    /// then exactly one of .finished/.failed) -- unless this send is itself
    /// superseded or reset before finishing, in which case onEvent simply
    /// stops being called for it (silent, by design -- see
    /// AgentExecutionFailure's doc comment).
    func send(
        prompt: String,
        history: [AgentConversationTurn],
        onDeviceAvailable: Bool,
        onEvent: @escaping @Sendable (AgentCoordinatorEvent) -> Void
    ) {
        cancel()

        let runtime: AgentRuntime
        let kind: AgentRuntimeKind
        if AgentRoutePolicy.decide(onDeviceAvailable: onDeviceAvailable) == .onDevice,
           let resolved = onDeviceRuntime(creatingIfNeeded: true) {
            runtime = resolved
            kind = .onDevice
        } else {
            runtime = cloudRuntime
            kind = .cloud
        }

        onEvent(.started(kind))
        activeTask = Task {
            do {
                try await runtime.send(
                    AgentRuntimeRequest(prompt: prompt, history: history),
                    onEvent: { event in
                        switch event {
                        case .textSnapshot(let text): onEvent(.textSnapshot(text))
                        }
                    }
                )
                // OnDeviceAgentRuntime can return normally after a
                // cancelled generation breaks out of its loop instead of
                // throwing -- guard against reporting that as .finished.
                guard !Task.isCancelled else { return }
                onEvent(.finished)
            } catch is CancellationError {
                // Superseded by a newer send() or resetConversation() --
                // silent, see AgentExecutionFailure's doc comment.
            } catch {
                onEvent(.failed(Self.normalize(error)))
            }
        }
    }

    private static func normalize(_ error: Error) -> AgentExecutionFailure {
        if case ScheduleAPIError.server(_, let code, _, _) = error, code == "RESOURCE_NOT_FOUND" {
            return .cloudConnectionRequired
        }
        return .runtimeFailure
    }
}
