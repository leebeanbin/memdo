import XCTest
import os
@testable import Memdo

final class CloudAgentRuntimeTests: XCTestCase {

    func test_agentChatTurnDTOs_mapsRolesAndContent() {
        let history: [AgentConversationTurn] = [
            .init(role: .user, content: "내일 3시에 회의 잡아줘"),
            .init(role: .assistant, content: "네, 잡아드릴게요."),
        ]
        let dtos = agentChatTurnDTOs(from: history)
        XCTAssertEqual(dtos.map(\.role), ["user", "assistant"])
        XCTAssertEqual(dtos.map(\.content), ["내일 3시에 회의 잡아줘", "네, 잡아드릴게요."])
    }

    func test_agentChatTurnDTOs_empty() {
        XCTAssertTrue(agentChatTurnDTOs(from: []).isEmpty)
    }

    // MARK: - AgentRuntime protocol sanity (via FakeAgentRuntime)

    func test_fakeRuntime_forwardsEventsInOrder() async throws {
        let fake = FakeAgentRuntime(kind: .cloud)
        fake.eventsToEmit = [.textSnapshot("a"), .textSnapshot("ab"), .textSnapshot("abc")]
        let received = OSAllocatedUnfairLock(initialState: [AgentRuntimeEvent]())
        try await fake.send(
            AgentRuntimeRequest(prompt: "hi", history: []),
            onEvent: { event in received.withLock { $0.append(event) } }
        )
        XCTAssertEqual(fake.sendCallCount, 1)
        if case .textSnapshot(let text) = received.withLock({ $0 }).last {
            XCTAssertEqual(text, "abc")
        } else {
            XCTFail("expected a textSnapshot event")
        }
    }
}
