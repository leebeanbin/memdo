import Foundation

// Agent-specific network DTOs, pulled out of ScheduleAPI.swift (second-pass
// structural review): ScheduleAPI.swift is the whole app's DTO/client
// layer (todos, calendars, categories, account, sync, search, ...), and
// these types are the one coherent cluster within it that D1-D4 keeps
// touching directly -- moving them here reduces churn on an otherwise
// unrelated file for every future Agent change. Plain data-transfer type
// declarations only; the actual API-calling methods (agentModels(),
// agentCloudChat(...), etc.) stay in ScheduleAPI.swift alongside the rest
// of the network client.

struct AgentKeyStatusResponseDTO: Decodable {
    let connected: Bool
}

struct AgentKeySaveRequestDTO: Encodable {
    let apiKey: String
}

/// Mirrors backend's ModelTier (model-registry-contract.ts) field for
/// field -- see that type's doc comment for the meaning of each case.
/// `.experimental` is gated behind a developer-only surface in the picker
/// (CloudAgentSettings.swift) rather than shown to every user: "selectable
/// for developer testing" is not the same as "recommended."
enum AgentModelTier: String, Decodable, Hashable {
    case recommended
    case freeAuto = "free-auto"
    case validatedFree = "validated-free"
    case experimental
}

struct AgentModelDTO: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let promptPricePerM: Double
    let completionPricePerM: Double
    let contextLength: Int
    let tier: AgentModelTier
    /// Snapshot from the last human-reviewed `eval:compare` promotion, not
    /// live telemetry -- nil until that model has been promoted at least
    /// once. See memdo-backend's model-registry-contract.ts.
    let latencyClass: String?
    let costClass: String?
    /// Pass rate over automatically-graded cases only (manualReview
    /// fixtures excluded from the denominator) -- NOT "% of the full eval
    /// corpus." Never present this as a fraction of all fixtures. Always
    /// nil for tier .freeAuto -- the backend never promotes a score for a
    /// non-deterministic router (see ModelTier's doc comment).
    let evalScore: Double?
}

struct AgentModelsResponseDTO: Decodable {
    let models: [AgentModelDTO]
}

struct AgentUsageItemDTO: Decodable, Identifiable {
    let model: String
    let costUsd: Double
    let createdAt: String

    var id: String { "\(createdAt):\(model)" }
}

struct AgentUsageResponseDTO: Decodable {
    let totalRequests: Int
    let totalCostUsd: Double
    let recent: [AgentUsageItemDTO]
}

struct AgentChatTurnDTO: Codable {
    let role: String
    let content: String
}

struct AgentChatRequestDTO: Encodable {
    let message: String
    let history: [AgentChatTurnDTO]
    let model: String?
    /// Founder/developer opt-in for the sanitized per-turn debug trace (D2)
    /// -- see backend's chatRequestSchema.debug doc comment for why a
    /// self-declared client flag is proportionate here (the trace is
    /// already sanitized and scoped to this request's own turn). Always
    /// DEBUG-build-only from this client -- see agentCloudChat(...).
    let debug: Bool
}

/// Field-for-field the same shape ProposeScheduleTool's Arguments produces
/// on-device, so both paths feed the exact same proposal/consent UI.
struct CloudProposedScheduleDTO: Decodable {
    let title: String
    let date: String
    let startTime: String?
    let endTime: String?
    let isTask: Bool
    let note: String?
    /// Set server-side by agent-cloud-chat's own Reflection check (see
    /// findConflict in agent-cloud-contract.ts) -- guaranteed, unlike the
    /// model's own optional search_schedules call.
    let conflictTitle: String?
    /// True when the Reflection check itself couldn't run (e.g. the existing-
    /// schedule fetch failed) -- distinct from conflictTitle being nil, which
    /// means the check ran and found nothing. Fail-closed: this is never
    /// silently treated as "no conflict."
    let conflictCheckFailed: Bool?
}

/// Mirrors propose_schedule_update's shape (agent-cloud-contract.ts) --
/// completing, moving, or deleting an EXISTING item. `title`/`version` are
/// echoed back by the server (the model only ever supplies an `id`), so the
/// client has what it needs to call the real todos API without a second
/// round trip.
struct CloudProposedScheduleUpdateDTO: Decodable {
    let id: String
    let action: String  // "complete" | "reschedule" | "delete"
    let date: String?
    let startTime: String?
    let endTime: String?
    let title: String
    let version: Int
    let conflictTitle: String?
    let conflictCheckFailed: Bool?
}

/// Mirrors propose_routine_update's shape (agent-cloud-contract.ts) -- every
/// field optional, since the model only includes the settings it's actually
/// proposing to change.
struct CloudProposedRoutineUpdateDTO: Decodable, Equatable {
    let dailyReviewEnabled: Bool?
    let dailyReviewTime: String?
    let newsBriefingEnabled: Bool?
    let newsBriefingTime: String?
    let planningPromptTime: String?
    let notificationsEnabled: Bool?
}

/// Mirrors propose_review_actions's shape (agent-cloud-contract.ts) -- a
/// proposed reflection *text* for one day. `date` is the model's raw token
/// ("today"/"tomorrow"/"yesterday"/yyyy-MM-dd), NOT resolved server-side --
/// resolving it is this client's job (see AgentDateExpression).
struct CloudProposedReviewActionDTO: Decodable, Equatable {
    let date: String
    let reflection: String
}

/// Mirrors request_clarification's shape (agent-cloud-contract.ts) -- staged
/// when the model needs more information instead of guessing. No approval UI
/// exists for this (see AgentIntent.swift's doc comment): the user's reply
/// flows into the next normal turn.
struct CloudClarificationRequestDTO: Decodable, Equatable {
    let question: String
    let missingFields: [String]?
    let reason: String?
}

/// Minimal type-erased JSON value for decoding the founder debug trace's
/// (D2) already-SANITIZED args/result values -- flat, small objects of
/// strings/numbers/booleans/short string arrays (see backend's
/// founder-debug-trace.ts), never the raw tool payload. Not worth a
/// fully-typed DTO per tool for a debug-only surface. Not meant to
/// round-trip; `debugDescription` is display-only.
enum AgentSanitizedValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AgentSanitizedValue])
    case array([AgentSanitizedValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: AgentSanitizedValue].self) { self = .object(value); return }
        if let value = try? container.decode([AgentSanitizedValue].self) { self = .array(value); return }
        self = .null
    }

    var debugDescription: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .array(let a): return "[" + a.map(\.debugDescription).joined(separator: ", ") + "]"
        case .object(let o):
            return "{" + o.sorted { $0.key < $1.key }
                .map { "\"\($0.key)\": \($0.value.debugDescription)" }
                .joined(separator: ", ") + "}"
        }
    }
}

/// One dispatched tool call as reported by the founder debug trace (D2) --
/// mirrors backend's `FounderDebugToolCall` (founder-debug-trace.ts).
/// `args`/`result` are already the SANITIZED per-tool projection built
/// server-side (dates, counts, structural flags, text LENGTHS) -- never a
/// raw title/note/reflection/question. `result` absent (not merely an
/// empty object) means the handler never actually ran to completion for
/// that call, mirroring the backend's own ToolDispatchState semantics.
struct AgentDebugToolCallDTO: Decodable {
    let name: String
    let args: [String: AgentSanitizedValue]
    let result: [String: AgentSanitizedValue]?
}

/// Mirrors backend's `FounderDebugTrace` (founder-debug-trace.ts) field for
/// field -- see that type's doc comment for why this is deliberately
/// separate from Epic H's agent_audit_log rather than a client-side read
/// of an audit row, and why `toolCalls` is a sanitized projection rather
/// than raw ToolDispatchState.dispatchedTools. Only present on the wire at
/// all when this request opted in (AgentChatRequestDTO.debug) -- absent,
/// not merely empty, for any client that didn't ask.
struct AgentDebugTraceDTO: Decodable {
    let requestedModel: String
    let resolvedModel: String?
    let latencyMs: Int
    let toolCalls: [AgentDebugToolCallDTO]
}

/// One line of the newline-delimited stream agent-cloud-chat responds with.
/// Every line has exactly one of these populated: `delta` while text is
/// still arriving, or `done`/`proposedSchedule`/`proposedScheduleUpdate`/
/// `proposedRoutineUpdate`/`proposedReviewAction`/`clarificationRequest` on
/// the terminal line, or `error` if something failed mid-stream.
/// `debugTrace` is a terminal-line addition, present only when this
/// request's `debug` flag was set.
struct AgentStreamLineDTO: Decodable {
    let delta: String?
    let done: Bool?
    let proposedSchedule: CloudProposedScheduleDTO?
    let proposedScheduleUpdate: CloudProposedScheduleUpdateDTO?
    let proposedRoutineUpdate: CloudProposedRoutineUpdateDTO?
    let proposedReviewAction: CloudProposedReviewActionDTO?
    let clarificationRequest: CloudClarificationRequestDTO?
    let toolNames: [String]?
    let debugTrace: AgentDebugTraceDTO?
    let error: String?
}

/// agentCloudChat's terminal result -- the model calls at most one propose_*
/// tool per turn, but all four (plus clarificationRequest) are carried
/// through so the caller doesn't need a sixth enum just to unwrap.
/// `toolNames` is the full dispatched-tool-name sequence, used by
/// classifyAgentIntent (AgentIntent.swift) to tell FIND_FREE_SLOTS/
/// SEARCH_SCHEDULES apart from ANSWER when no proposal/clarification field
/// is set. `debugTrace` backs the founder debug trace (D2) -- nil unless
/// this request opted in via `debug` AND the model actually called a tool.
struct AgentCloudChatResult {
    let proposedSchedule: CloudProposedScheduleDTO?
    let proposedScheduleUpdate: CloudProposedScheduleUpdateDTO?
    let proposedRoutineUpdate: CloudProposedRoutineUpdateDTO?
    let proposedReviewAction: CloudProposedReviewActionDTO?
    let clarificationRequest: CloudClarificationRequestDTO?
    let toolNames: [String]
    let debugTrace: AgentDebugTraceDTO?
}
