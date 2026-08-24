@testable import Memdo

/// Test double for AgentRuntime -- lets AgentCoordinator tests (and this
/// file's own sanity checks) drive routing/cancellation/event-forwarding
/// without touching FoundationModels or the network.
final class FakeAgentRuntime: AgentRuntime, @unchecked Sendable {
    let kind: AgentRuntimeKind
    let capabilities: AgentRuntimeCapabilities

    private(set) var sendCallCount = 0
    private(set) var lastRequest: AgentRuntimeRequest?

    /// Events to emit, in order, before returning. Empty by default.
    var eventsToEmit: [AgentRuntimeEvent] = []
    /// Thrown after emitting eventsToEmit, if set.
    var errorToThrow: Error?
    /// Set true to make send() await this before returning -- lets a test
    /// hold a call in flight to exercise cancellation.
    var shouldHang = false

    init(kind: AgentRuntimeKind = .onDevice) {
        self.kind = kind
        self.capabilities = kind.capabilities
    }

    func send(
        _ request: AgentRuntimeRequest,
        onEvent: @escaping @Sendable (AgentRuntimeEvent) -> Void
    ) async throws {
        sendCallCount += 1
        lastRequest = request
        for event in eventsToEmit {
            onEvent(event)
        }
        if shouldHang {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw CancellationError()
        }
        if let errorToThrow {
            throw errorToThrow
        }
    }
}
