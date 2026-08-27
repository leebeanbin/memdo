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

    // MARK: - AgentTraceJSONValue / AgentDebugTrace (D2 founder trace)

    func test_agentTraceJSONValue_decodesEveryJSONShape() throws {
        func decode(_ json: String) throws -> AgentTraceJSONValue {
            try JSONDecoder().decode(AgentTraceJSONValue.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode("\"hi\"").debugDescription, "\"hi\"")
        XCTAssertEqual(try decode("60").debugDescription, "60")
        XCTAssertEqual(try decode("1.5").debugDescription, "1.5")
        XCTAssertEqual(try decode("true").debugDescription, "true")
        XCTAssertEqual(try decode("null").debugDescription, "null")
        XCTAssertEqual(try decode("[1,2]").debugDescription, "[1, 2]")
        XCTAssertEqual(try decode(#"{"b":2,"a":1}"#).debugDescription, "{\"a\": 1, \"b\": 2}")
    }

    func test_agentDebugTrace_combinesBackendTraceWithClientKnownIntent() throws {
        let dto = AgentTurnTraceDTO(requestedModel: "openrouter/free", resolvedModel: "nvidia/nemotron-3-super-120b-a12b:free", latencyMs: 842)
        let toolCall = AgentTraceToolCallDTO(
            name: "find_free_slots",
            args: try JSONDecoder().decode(AgentTraceJSONValue.self, from: Data(#"{"scope":"today"}"#.utf8)),
            result: try JSONDecoder().decode(AgentTraceJSONValue.self, from: Data(#"{"slots":["08:00-22:00"]}"#.utf8))
        )
        // intent is a client-side concept (AgentIntent.swift) the backend
        // trace payload never carries -- AgentDebugTrace.init is the one
        // place it gets folded in alongside the backend's own fields.
        let trace = AgentDebugTrace(trace: dto, dispatchedTools: [toolCall], intent: .findFreeSlots)

        XCTAssertEqual(trace.requestedModel, "openrouter/free")
        XCTAssertEqual(trace.resolvedModel, "nvidia/nemotron-3-super-120b-a12b:free")
        XCTAssertEqual(trace.latencyMs, 842)
        XCTAssertEqual(trace.intent, .findFreeSlots)
        XCTAssertEqual(trace.toolCalls.count, 1)
        XCTAssertEqual(trace.toolCalls[0].name, "find_free_slots")

        let text = trace.debugText
        XCTAssertTrue(text.contains("openrouter/free"))
        XCTAssertTrue(text.contains("nvidia/nemotron-3-super-120b-a12b:free"))
        XCTAssertTrue(text.contains("find_free_slots"))
        XCTAssertTrue(text.contains("842ms"))
    }
}
