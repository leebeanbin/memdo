import Foundation

/// Founder/debug-only per-turn trace (D2) -- combines the cloud backend's
/// already-SANITIZED AgentDebugTraceDTO payload (founder-debug-trace.ts on
/// the backend built it; ScheduleAPI.swift's AgentSanitizedValue decodes
/// it) with `intent`, a client-side classification concept
/// (AgentIntent.swift) the backend doesn't compute. Deliberately NOT
/// sourced from agent_audit_log (Epic H's backend execution observability)
/// -- see AgentDebugTraceDTO's doc comment. On-device turns don't populate
/// this: the on-device tool-calling loop has no per-call event to build a
/// comparable trace from today (a real, larger gap noted separately, not
/// closed by this slice).
///
/// Pulled out of AssistantView.swift (second-pass structural review): this
/// is a debug-DTO-projection-plus-text-rendering model, not view code --
/// nothing here touches SwiftUI, and it's independently unit-testable.
struct AgentDebugTrace: Equatable {
    struct ToolCall: Equatable {
        let name: String
        let argsDescription: String
        let resultDescription: String
    }

    let requestedModel: String
    let resolvedModel: String?
    let latencyMs: Int
    let toolCalls: [ToolCall]
    let intent: AgentIntent?

    init(trace: AgentDebugTraceDTO, intent: AgentIntent?) {
        requestedModel = trace.requestedModel
        resolvedModel = trace.resolvedModel
        latencyMs = trace.latencyMs
        toolCalls = trace.toolCalls.map {
            ToolCall(
                name: $0.name,
                argsDescription: Self.describe($0.args),
                resultDescription: $0.result.map(Self.describe) ?? "–"
            )
        }
        self.intent = intent
    }

    private static func describe(_ fields: [String: AgentSanitizedValue]) -> String {
        AgentSanitizedValue.object(fields).debugDescription
    }

    /// Plain-text rendering for the minimal founder debug sheet -- not
    /// meant to be pretty, just legible enough to answer "why did this
    /// answer happen." Every value here is already the backend's sanitized
    /// projection (founder-debug-trace.ts) -- this renderer has no
    /// redaction responsibility of its own.
    var debugText: String {
        var lines = [
            "requested: \(requestedModel)",
            "resolved: \(resolvedModel ?? "(같음/모름)")",
            "intent: \(intent.map { String(describing: $0) } ?? "미분류")",
            "latency: \(latencyMs)ms",
            "",
        ]
        if toolCalls.isEmpty {
            lines.append("tool calls: 없음")
        } else {
            lines.append("tool calls:")
            for (index, call) in toolCalls.enumerated() {
                lines.append("\(index + 1). \(call.name)")
                lines.append("   args: \(call.argsDescription)")
                lines.append("   result: \(call.resultDescription)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
