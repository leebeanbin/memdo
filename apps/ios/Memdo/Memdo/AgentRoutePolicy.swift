import Foundation

/// Deterministic on-device/cloud selection -- the only place this decision
/// is made (AssistantView no longer checks SystemLanguageModel.default.availability
/// itself). Deliberately a function of on-device availability alone: whether
/// the cloud connection actually works isn't knowable synchronously (there's
/// no local signal for it -- the backend's response is the only source of
/// truth), so it's not a routing input. A cloud call that turns out to need
/// a connection surfaces as AgentExecutionFailure.cloudConnectionRequired at
/// execution time instead, the same way the current RESOURCE_NOT_FOUND catch
/// in AssistantView already works today.
enum AgentRoutePolicy {
    static func decide(onDeviceAvailable: Bool) -> AgentRuntimeKind {
        onDeviceAvailable ? .onDevice : .cloud
    }
}
