import XCTest
import os
@testable import Memdo

final class AgentToolActivityTests: XCTestCase {

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
        // must stay nil rather than guessing a wording -- an unmapped tool
        // must never fabricate a hint (Part E requirement).
        XCTAssertNil(cloudToolCapability(forRawName: "request_clarification"))
        XCTAssertNil(cloudToolCapability(forRawName: "some_future_tool"))
    }

    // MARK: - toolHintText (D4)

    func test_toolHintText_isExhaustiveAndNonEmptyForEveryCapability() {
        let allCapabilities: [AgentCapability] = [
            .scheduleSearch, .freeSlotSearch, .proposeSchedule, .proposeScheduleUpdate,
            .dayContext, .routinePreferences, .reviewHistory,
            .proposeRoutineUpdate, .proposeReviewActions,
        ]
        for capability in allCapabilities {
            XCTAssertFalse(toolHintText(for: capability).isEmpty)
        }
    }

    func test_toolHintText_groupsReadOnlyContextToolsUnderOneWording() {
        XCTAssertEqual(toolHintText(for: .dayContext), toolHintText(for: .routinePreferences))
        XCTAssertEqual(toolHintText(for: .routinePreferences), toolHintText(for: .reviewHistory))
    }

    func test_toolHintText_groupsEveryProposeToolUnderOneWording() {
        let wording = toolHintText(for: .proposeSchedule)
        XCTAssertEqual(toolHintText(for: .proposeScheduleUpdate), wording)
        XCTAssertEqual(toolHintText(for: .proposeRoutineUpdate), wording)
        XCTAssertEqual(toolHintText(for: .proposeReviewActions), wording)
    }

    // MARK: - AgentToolActivitySink (D4 + second-pass start/finish lifecycle)

    func test_activitySink_reportsOnlyToTheActiveHandler() {
        let sink = AgentToolActivitySink()
        let received = OSAllocatedUnfairLock(initialState: [AgentRuntimeEvent]())
        sink.reportStarted(.freeSlotSearch) // no active handler yet -- silently dropped
        XCTAssertTrue(received.withLock { $0 }.isEmpty)

        sink.setActive { event in received.withLock { $0.append(event) } }
        sink.reportStarted(.freeSlotSearch)
        sink.reportFinished(.freeSlotSearch)
        XCTAssertEqual(received.withLock { $0 }.count, 2)

        sink.setActive(nil)
        sink.reportStarted(.scheduleSearch)
        XCTAssertEqual(
            received.withLock { $0 }.count, 2,
            "cleared sink must not still forward"
        )
    }

    func test_activitySink_reportStartedAndReportFinishedProduceDistinctEvents() {
        let sink = AgentToolActivitySink()
        let received = OSAllocatedUnfairLock(initialState: [AgentRuntimeEvent]())
        sink.setActive { event in received.withLock { $0.append(event) } }

        sink.reportStarted(.freeSlotSearch)
        sink.reportFinished(.freeSlotSearch)

        let events = received.withLock { $0 }
        guard case .toolCallStarted(let startedCapability) = events[0] else {
            return XCTFail("expected .toolCallStarted first")
        }
        guard case .toolCallFinished(let finishedCapability) = events[1] else {
            return XCTFail("expected .toolCallFinished second")
        }
        XCTAssertEqual(startedCapability, .freeSlotSearch)
        XCTAssertEqual(finishedCapability, .freeSlotSearch)
    }

    // Part E: "sequential tools replace hints correctly" at the signal
    // layer -- a second reportStarted for a different capability, with no
    // reportFinished in between, still produces its own distinct
    // .toolCallStarted event in order. (The View-layer guarantee that this
    // actually replaces the displayed hint is AssistantView.handleCoordinatorEvent's
    // job; this pins the signal sequence it consumes.)
    func test_activitySink_sequentialStartsProduceEventsInOrder() {
        let sink = AgentToolActivitySink()
        let received = OSAllocatedUnfairLock(initialState: [AgentCapability]())
        sink.setActive { event in
            if case .toolCallStarted(let capability) = event {
                received.withLock { $0.append(capability) }
            }
        }
        sink.reportStarted(.scheduleSearch)
        sink.reportFinished(.scheduleSearch)
        sink.reportStarted(.proposeSchedule)
        sink.reportFinished(.proposeSchedule)
        XCTAssertEqual(received.withLock { $0 }, [.scheduleSearch, .proposeSchedule])
    }
}
