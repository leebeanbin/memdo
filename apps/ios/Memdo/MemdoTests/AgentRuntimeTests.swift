import XCTest
@testable import Memdo

final class AgentRuntimeTests: XCTestCase {

    // MARK: - AgentRoutePolicy

    func test_routePolicy_onDeviceAvailable_usesOnDevice() {
        XCTAssertEqual(AgentRoutePolicy.decide(onDeviceAvailable: true), .onDevice)
    }

    func test_routePolicy_onDeviceUnavailable_usesCloud() {
        XCTAssertEqual(AgentRoutePolicy.decide(onDeviceAvailable: false), .cloud)
    }

    // MARK: - AgentRuntimeCapabilities

    func test_onDeviceCapabilities_supportsOnlyToolBackedCapabilities() {
        let capabilities = AgentRuntimeKind.onDevice.capabilities
        for capability: AgentCapability in [.freeSlotSearch, .proposeSchedule, .proposeScheduleUpdate] {
            XCTAssertTrue(capabilities.supports(capability), "expected on-device to support \(capability)")
        }
        for capability: AgentCapability in [
            .scheduleSearch, .dayContext, .routinePreferences, .reviewHistory,
            .proposeRoutineUpdate, .proposeReviewActions,
        ] {
            XCTAssertFalse(capabilities.supports(capability), "expected on-device NOT to support \(capability)")
        }
    }

    func test_cloudCapabilities_supportsAllNineTools() {
        let capabilities = AgentRuntimeKind.cloud.capabilities
        let allCapabilities: [AgentCapability] = [
            .scheduleSearch, .freeSlotSearch, .proposeSchedule, .proposeScheduleUpdate,
            .dayContext, .routinePreferences, .reviewHistory,
            .proposeRoutineUpdate, .proposeReviewActions,
        ]
        for capability in allCapabilities {
            XCTAssertTrue(capabilities.supports(capability), "expected cloud to support \(capability)")
        }
        XCTAssertEqual(capabilities.supported.count, allCapabilities.count)
    }
}
