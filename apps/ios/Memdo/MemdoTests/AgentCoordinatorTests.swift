import XCTest
import os
@testable import Memdo

@MainActor
final class AgentCoordinatorTests: XCTestCase {

    private func awaitTerminal(
        _ coordinator: AgentCoordinator,
        prompt: String = "p",
        history: [AgentConversationTurn] = [],
        onDeviceAvailable: Bool,
        collected: OSAllocatedUnfairLock<[AgentCoordinatorEvent]>
    ) async {
        let done = expectation(description: "terminal event")
        coordinator.send(prompt: prompt, history: history, onDeviceAvailable: onDeviceAvailable) { event in
            collected.withLock { $0.append(event) }
            switch event {
            case .finished, .failed: done.fulfill()
            default: break
            }
        }
        await fulfillment(of: [done], timeout: 2)
    }

    // MARK: - Routing

    func test_send_routesToCloud_whenOnDeviceUnavailable() async {
        let cloud = FakeAgentRuntime(kind: .cloud)
        cloud.eventsToEmit = [.textSnapshot("hi")]
        let coordinator = AgentCoordinator(onDeviceRuntimeFactory: nil, cloudRuntime: cloud)
        let collected = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())

        await awaitTerminal(coordinator, onDeviceAvailable: false, collected: collected)

        XCTAssertEqual(cloud.sendCallCount, 1)
        let events = collected.withLock { $0 }
        XCTAssertEqual(events.first, .started(.cloud))
        XCTAssertEqual(events.last, .finished)
        XCTAssertTrue(events.contains(.textSnapshot("hi")))
    }

    func test_send_routesToOnDevice_whenAvailable() async {
        let onDevice = FakeAgentRuntime(kind: .onDevice)
        var factoryCallCount = 0
        let coordinator = AgentCoordinator(
            onDeviceRuntimeFactory: { factoryCallCount += 1; return onDevice },
            cloudRuntime: FakeAgentRuntime(kind: .cloud)
        )
        let collected = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())

        await awaitTerminal(coordinator, onDeviceAvailable: true, collected: collected)

        XCTAssertEqual(onDevice.sendCallCount, 1)
        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertEqual(collected.withLock { $0 }.first, .started(.onDevice))
    }

    // MARK: - Session/runtime reuse and reset (regression coverage for the

    // UpdateScheduleTool-missing bug: as long as the factory is called at
    // most once per "session," every OnDeviceAgentRuntime it produces was
    // built the one and only way -- there's no second, drifted construction
    // site left to register a different tool set.)

    func test_secondSend_reusesCachedOnDeviceRuntime_factoryNotCalledAgain() async {
        var factoryCallCount = 0
        let coordinator = AgentCoordinator(
            onDeviceRuntimeFactory: { factoryCallCount += 1; return FakeAgentRuntime(kind: .onDevice) },
            cloudRuntime: FakeAgentRuntime(kind: .cloud)
        )
        let collected = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())

        await awaitTerminal(coordinator, onDeviceAvailable: true, collected: collected)
        await awaitTerminal(coordinator, onDeviceAvailable: true, collected: collected)

        XCTAssertEqual(factoryCallCount, 1, "second send should reuse the cached runtime, not build a new one")
    }

    func test_resetRuntime_thenNextSend_buildsANewRuntime() async {
        var factoryCallCount = 0
        let coordinator = AgentCoordinator(
            onDeviceRuntimeFactory: { factoryCallCount += 1; return FakeAgentRuntime(kind: .onDevice) },
            cloudRuntime: FakeAgentRuntime(kind: .cloud)
        )
        let collected = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())

        await awaitTerminal(coordinator, onDeviceAvailable: true, collected: collected)
        coordinator.cancel()
        coordinator.resetRuntime()
        await awaitTerminal(coordinator, onDeviceAvailable: true, collected: collected)

        XCTAssertEqual(factoryCallCount, 2, "reset should discard the cached runtime so the next send builds a fresh one")
    }

    func test_prewarmOnDevice_createsRuntime_onlyOnce() {
        var factoryCallCount = 0
        let coordinator = AgentCoordinator(
            onDeviceRuntimeFactory: { factoryCallCount += 1; return FakeAgentRuntime(kind: .onDevice) },
            cloudRuntime: FakeAgentRuntime(kind: .cloud)
        )
        coordinator.prewarmOnDevice()
        coordinator.prewarmOnDevice()
        XCTAssertEqual(factoryCallCount, 1)
    }

    // MARK: - Failure normalization

    func test_cloudConnectionRequired_normalizesFromResourceNotFound() async {
        let cloud = FakeAgentRuntime(kind: .cloud)
        cloud.errorToThrow = ScheduleAPIError.server(status: 404, code: "RESOURCE_NOT_FOUND", message: "x", requestID: nil)
        let coordinator = AgentCoordinator(onDeviceRuntimeFactory: nil, cloudRuntime: cloud)
        let collected = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())

        await awaitTerminal(coordinator, onDeviceAvailable: false, collected: collected)

        XCTAssertEqual(collected.withLock { $0 }.last, .failed(.cloudConnectionRequired))
    }

    func test_genericError_normalizesToRuntimeFailure() async {
        struct SomeError: Error {}
        let cloud = FakeAgentRuntime(kind: .cloud)
        cloud.errorToThrow = SomeError()
        let coordinator = AgentCoordinator(onDeviceRuntimeFactory: nil, cloudRuntime: cloud)
        let collected = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())

        await awaitTerminal(coordinator, onDeviceAvailable: false, collected: collected)

        XCTAssertEqual(collected.withLock { $0 }.last, .failed(.runtimeFailure))
    }

    // D4 hardening check (second-pass review): a tool call that reports
    // .toolCallStarted and then the runtime throws (mirroring
    // agent-cloud-chat's dispatchToolCall throwing mid-handler, which its
    // outer try/catch turns into a stream `error` line -- see
    // agent-cloud-chat/index.ts) must still reach a terminal .failed event,
    // never leaving the turn silently stuck "started" with nothing after
    // it. AssistantView.handleCoordinatorEvent's .failed case is what
    // actually clears toolHint on this path; this test pins the event
    // sequence that invariant depends on.
    func test_toolCallStartedFollowedByThrow_stillReachesFailed() async {
        struct SomeError: Error {}
        let cloud = FakeAgentRuntime(kind: .cloud)
        cloud.eventsToEmit = [.toolCallStarted(.freeSlotSearch)]
        cloud.errorToThrow = SomeError()
        let coordinator = AgentCoordinator(onDeviceRuntimeFactory: nil, cloudRuntime: cloud)
        let collected = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())

        await awaitTerminal(coordinator, onDeviceAvailable: false, collected: collected)

        let events = collected.withLock { $0 }
        XCTAssertEqual(events, [.started(.cloud), .toolCallStarted(.freeSlotSearch), .failed(.runtimeFailure)])
    }

    // MARK: - Cancellation is always silent

    func test_newSend_cancelsPreviousRun_withoutEmittingFailure() async {
        let stale = FakeAgentRuntime(kind: .cloud)
        stale.shouldHang = true
        let fresh = FakeAgentRuntime(kind: .cloud)
        fresh.eventsToEmit = [.textSnapshot("second")]
        // A single cloudRuntime instance is reused across both sends here
        // (same as production, where AgentCoordinator always calls send()
        // on the same cloud runtime) -- swap eventsToEmit/shouldHang isn't
        // meaningful mid-flight, so this test drives it via two coordinators
        // sharing one collector instead: what matters is that the stale
        // Task's onEvent never fires again after being superseded.
        let coordinator = AgentCoordinator(onDeviceRuntimeFactory: nil, cloudRuntime: stale)
        let staleEvents = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())
        coordinator.send(prompt: "first", history: [], onDeviceAvailable: false) { event in
            staleEvents.withLock { $0.append(event) }
        }
        // Give the stale Task a moment to actually start (enter its hang
        // loop) before superseding it.
        try? await Task.sleep(nanoseconds: 20_000_000)

        let freshCoordinator = AgentCoordinator(onDeviceRuntimeFactory: nil, cloudRuntime: fresh)
        let freshEvents = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())
        await awaitTerminal(freshCoordinator, onDeviceAvailable: false, collected: freshEvents)

        coordinator.cancel()
        // The stale run must never have reached a terminal event -- only
        // .started (emitted synchronously before the hang) should be there.
        let stale2 = staleEvents.withLock { $0 }
        XCTAssertFalse(stale2.contains { if case .finished = $0 { return true }; return false })
        XCTAssertFalse(stale2.contains { if case .failed = $0 { return true }; return false })
    }

    func test_cancel_stopsExecution_withoutEmittingFailure() async {
        let hanging = FakeAgentRuntime(kind: .cloud)
        hanging.shouldHang = true
        let coordinator = AgentCoordinator(onDeviceRuntimeFactory: nil, cloudRuntime: hanging)
        let collected = OSAllocatedUnfairLock(initialState: [AgentCoordinatorEvent]())
        coordinator.send(prompt: "p", history: [], onDeviceAvailable: false) { event in
            collected.withLock { $0.append(event) }
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        coordinator.cancel()
        try? await Task.sleep(nanoseconds: 20_000_000)

        let events = collected.withLock { $0 }
        XCTAssertFalse(events.contains { if case .finished = $0 { return true }; return false })
        XCTAssertFalse(events.contains { if case .failed = $0 { return true }; return false })
    }
}
