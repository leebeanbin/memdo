import Foundation

/// Which execution path an Agent turn runs on. Provider-neutral by design --
/// no model ID or FoundationModels/OpenRouter-specific type belongs here or
/// anywhere in AgentCapability/AgentRoutePolicy.
enum AgentRuntimeKind: Equatable, Sendable {
    case onDevice
    case cloud
}

/// Product/domain vocabulary for what an Agent turn can do -- not a 1:1 tool
/// name mapping, so a future tool rename doesn't ripple into routing/UI code
/// that only cares about capability.
enum AgentCapability: Hashable, Sendable {
    case scheduleSearch
    case freeSlotSearch

    case proposeSchedule
    case proposeScheduleUpdate

    case dayContext
    case routinePreferences
    case reviewHistory

    case proposeRoutineUpdate
    case proposeReviewActions
}

struct AgentRuntimeCapabilities: Equatable, Sendable {
    let supported: Set<AgentCapability>

    func supports(_ capability: AgentCapability) -> Bool {
        supported.contains(capability)
    }
}

extension AgentRuntimeKind {
    /// Mirrors docs/20-ai-agent-architecture.md §5's tool grouping -- the
    /// on-device set is 3 FoundationModels Tools (AgentTools.swift), the
    /// cloud set is the 9 entries in agent-cloud-contract.ts's toolHandlers.
    var capabilities: AgentRuntimeCapabilities {
        switch self {
        case .onDevice:
            .init(supported: [
                .freeSlotSearch,
                .proposeSchedule,
                .proposeScheduleUpdate,
            ])

        case .cloud:
            .init(supported: [
                .scheduleSearch,
                .freeSlotSearch,
                .proposeSchedule,
                .proposeScheduleUpdate,
                .dayContext,
                .routinePreferences,
                .reviewHistory,
                .proposeRoutineUpdate,
                .proposeReviewActions,
            ])
        }
    }
}
