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

    // MARK: - AgentSanitizedValue / AgentStreamLineDTO.debugTrace (D2 founder trace)

    func test_agentSanitizedValue_decodesEveryJSONShape() throws {
        func decode(_ json: String) throws -> AgentSanitizedValue {
            try JSONDecoder().decode(AgentSanitizedValue.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode("\"hi\"").debugDescription, "\"hi\"")
        XCTAssertEqual(try decode("60").debugDescription, "60")
        XCTAssertEqual(try decode("1.5").debugDescription, "1.5")
        XCTAssertEqual(try decode("true").debugDescription, "true")
        XCTAssertEqual(try decode("null").debugDescription, "null")
        XCTAssertEqual(try decode("[1,2]").debugDescription, "[1, 2]")
        XCTAssertEqual(try decode(#"{"b":2,"a":1}"#).debugDescription, "{\"a\": 1, \"b\": 2}")
    }

    func test_agentStreamLineDTO_decodesASanitizedDebugTrace() throws {
        let json = """
        {"done": true, "toolNames": ["find_free_slots"], "debugTrace": {
            "requestedModel": "openrouter/free",
            "resolvedModel": "nvidia/nemotron-3-super-120b-a12b:free",
            "latencyMs": 842,
            "toolCalls": [{"name": "find_free_slots", "args": {"scope": "today"}, "result": {"slotCount": 1}}]
        }}
        """
        let parsed = try JSONDecoder().decode(AgentStreamLineDTO.self, from: Data(json.utf8))
        let trace = try XCTUnwrap(parsed.debugTrace)
        XCTAssertEqual(trace.requestedModel, "openrouter/free")
        XCTAssertEqual(trace.resolvedModel, "nvidia/nemotron-3-super-120b-a12b:free")
        XCTAssertEqual(trace.latencyMs, 842)
        XCTAssertEqual(trace.toolCalls.count, 1)
        XCTAssertEqual(trace.toolCalls[0].name, "find_free_slots")
        XCTAssertNotNil(trace.toolCalls[0].result)
    }

    func test_agentStreamLineDTO_debugTraceAbsentWhenNotRequested() throws {
        let json = #"{"done": true, "toolNames": []}"#
        let parsed = try JSONDecoder().decode(AgentStreamLineDTO.self, from: Data(json.utf8))
        XCTAssertNil(parsed.debugTrace)
    }

    // MARK: - AgentModelDTO.tier (D3 free-model tier)

    func test_agentModelDTO_decodesEveryTierRawValue() throws {
        func decode(tier: String) throws -> AgentModelTier {
            let json = """
            {"id": "x", "name": "X", "promptPricePerM": 0, "completionPricePerM": 0, \
            "contextLength": 100, "tier": "\(tier)", "latencyClass": null, "costClass": null, \
            "evalScore": null}
            """
            return try JSONDecoder().decode(AgentModelDTO.self, from: Data(json.utf8)).tier
        }
        XCTAssertEqual(try decode(tier: "recommended"), .recommended)
        XCTAssertEqual(try decode(tier: "free-auto"), .freeAuto)
        XCTAssertEqual(try decode(tier: "validated-free"), .validatedFree)
        XCTAssertEqual(try decode(tier: "experimental"), .experimental)
    }

    // MARK: - AgentStreamLineDTO.toolCallStarted (D4)

    func test_agentStreamLineDTO_decodesToolCallStarted() throws {
        let json = #"{"toolCallStarted": "find_free_slots"}"#
        let parsed = try JSONDecoder().decode(AgentStreamLineDTO.self, from: Data(json.utf8))
        XCTAssertEqual(parsed.toolCallStarted, "find_free_slots")
        XCTAssertNil(parsed.delta)
        XCTAssertNil(parsed.done)
    }

    func test_agentStreamLineDTO_toolCallStartedAbsentOnADeltaLine() throws {
        let json = #"{"delta": "안녕"}"#
        let parsed = try JSONDecoder().decode(AgentStreamLineDTO.self, from: Data(json.utf8))
        XCTAssertNil(parsed.toolCallStarted)
        XCTAssertEqual(parsed.delta, "안녕")
    }
}
