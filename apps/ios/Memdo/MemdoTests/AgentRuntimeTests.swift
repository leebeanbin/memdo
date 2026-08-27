import XCTest
import os
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

    // MARK: - cloudToolCapability (D4)

    func test_cloudToolCapability_mapsEveryReadAndProposeTool() {
        XCTAssertEqual(cloudToolCapability(forRawName: "search_schedules"), .scheduleSearch)
        XCTAssertEqual(cloudToolCapability(forRawName: "find_free_slots"), .freeSlotSearch)
        XCTAssertEqual(cloudToolCapability(forRawName: "propose_schedule"), .proposeSchedule)
        XCTAssertEqual(cloudToolCapability(forRawName: "propose_schedule_update"), .proposeScheduleUpdate)
        XCTAssertEqual(cloudToolCapability(forRawName: "get_day_context"), .dayContext)
        XCTAssertEqual(cloudToolCapability(forRawName: "get_routine_preferences"), .routinePreferences)
        XCTAssertEqual(cloudToolCapability(forRawName: "propose_routine_update"), .proposeRoutineUpdate)
        XCTAssertEqual(cloudToolCapability(forRawName: "get_review_history"), .reviewHistory)
        XCTAssertEqual(cloudToolCapability(forRawName: "propose_review_actions"), .proposeReviewActions)
    }

    func test_cloudToolCapability_returnsNilForClarificationAndUnknownNames() {
        // request_clarification's own response text is the user-facing
        // signal -- no separate mid-turn hint makes sense for it, so this
        // must stay nil rather than guessing a wording.
        XCTAssertNil(cloudToolCapability(forRawName: "request_clarification"))
        XCTAssertNil(cloudToolCapability(forRawName: "some_future_tool"))
    }

    // MARK: - AgentToolActivitySink (D4)

    func test_activitySink_reportsOnlyToTheActiveHandler() {
        let sink = AgentToolActivitySink()
        let received = OSAllocatedUnfairLock(initialState: [AgentCapability]())
        sink.report(.freeSlotSearch) // no active handler yet -- silently dropped
        XCTAssertTrue(received.withLock { $0 }.isEmpty)

        sink.setActive { capability in received.withLock { $0.append(capability) } }
        sink.report(.freeSlotSearch)
        sink.report(.proposeSchedule)
        XCTAssertEqual(received.withLock { $0 }, [.freeSlotSearch, .proposeSchedule])

        sink.setActive(nil)
        sink.report(.scheduleSearch)
        XCTAssertEqual(
            received.withLock { $0 }, [.freeSlotSearch, .proposeSchedule],
            "cleared sink must not still forward"
        )
    }
}
