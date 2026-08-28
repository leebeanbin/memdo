import XCTest
@testable import Memdo

final class AgentDebugTraceTests: XCTestCase {

    private func toolCallDTO(name: String, args: String, result: String?) throws -> AgentDebugToolCallDTO {
        let json = """
        {"name": "\(name)", "args": \(args)\(result.map { #", "result": \#($0)"# } ?? "")}
        """
        return try JSONDecoder().decode(AgentDebugToolCallDTO.self, from: Data(json.utf8))
    }

    func test_agentDebugTrace_combinesBackendTraceWithClientKnownIntent() throws {
        let toolCall = try toolCallDTO(
            name: "find_free_slots",
            args: #"{"scope":"today"}"#,
            result: #"{"slotCount":1}"#
        )
        let dto = AgentDebugTraceDTO(
            requestedModel: "openrouter/free",
            resolvedModel: "nvidia/nemotron-3-super-120b-a12b:free",
            latencyMs: 842,
            toolCalls: [toolCall]
        )
        // intent is a client-side concept (AgentIntent.swift) the backend
        // trace payload never carries -- AgentDebugTrace.init is the one
        // place it gets folded in alongside the backend's own fields.
        let trace = AgentDebugTrace(trace: dto, intent: .findFreeSlots)

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

    // D2 second-pass review: this trace must only ever render the backend's
    // already-sanitized fields -- it has no redaction logic of its own, so
    // this pins that a sanitized args/result dictionary renders faithfully
    // (lengths/counts/flags) without this layer trying to be "smart" about
    // it in a way that could reintroduce raw text by accident.
    func test_agentDebugTrace_rendersSanitizedFieldsVerbatimNeverRawText() throws {
        let toolCall = try toolCallDTO(
            name: "propose_schedule",
            args: #"{"date":"tomorrow","titleLength":12,"noteLength":40}"#,
            result: #"{"ok":true,"hasConflict":false,"checkFailed":false}"#
        )
        let dto = AgentDebugTraceDTO(requestedModel: "openai/gpt-5.4-mini", resolvedModel: nil, latencyMs: 10, toolCalls: [toolCall])
        let trace = AgentDebugTrace(trace: dto, intent: .proposeSchedule)

        XCTAssertTrue(trace.toolCalls[0].argsDescription.contains("titleLength"))
        XCTAssertTrue(trace.toolCalls[0].argsDescription.contains("12"))
        XCTAssertFalse(trace.toolCalls[0].argsDescription.contains("title\":"))
        XCTAssertTrue(trace.toolCalls[0].resultDescription.contains("hasConflict"))
    }

    func test_agentDebugTrace_missingResultRendersAsPlaceholder() throws {
        let toolCall = try toolCallDTO(name: "find_free_slots", args: #"{"scope":"today"}"#, result: nil)
        let dto = AgentDebugTraceDTO(requestedModel: "openai/gpt-5.4-mini", resolvedModel: nil, latencyMs: 5, toolCalls: [toolCall])
        let trace = AgentDebugTrace(trace: dto, intent: nil)
        XCTAssertEqual(trace.toolCalls[0].resultDescription, "–")
    }

    func test_agentDebugTrace_emptyToolCallsRendersNoneRatherThanOmittingTheLine() {
        let dto = AgentDebugTraceDTO(requestedModel: "openai/gpt-5.4-mini", resolvedModel: nil, latencyMs: 1, toolCalls: [])
        let trace = AgentDebugTrace(trace: dto, intent: .answer)
        XCTAssertTrue(trace.debugText.contains("tool calls: 없음"))
    }
}
