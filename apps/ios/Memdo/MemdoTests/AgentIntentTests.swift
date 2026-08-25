import XCTest
@testable import Memdo

final class AgentIntentTests: XCTestCase {
    func test_yesterday_parsesToken() {
        XCTAssertEqual(AgentDateExpression(token: "yesterday"), .yesterday)
    }

    func test_yesterday_resolvesToExactlyOneDayBeforeToday() {
        let calendar = Calendar.current
        let today = AgentDateExpression.today.resolvedDate(calendar: calendar)
        let yesterday = AgentDateExpression.yesterday.resolvedDate(calendar: calendar)
        XCTAssertNotEqual(yesterday, today)
        XCTAssertEqual(calendar.date(byAdding: .day, value: 1, to: yesterday), today)
    }

    func test_today_and_tomorrow_stillResolveCorrectly() {
        let calendar = Calendar.current
        let today = AgentDateExpression.today.resolvedDate(calendar: calendar)
        let tomorrow = AgentDateExpression.tomorrow.resolvedDate(calendar: calendar)
        XCTAssertEqual(calendar.date(byAdding: .day, value: 1, to: today), tomorrow)
    }

    func test_unknownToken_returnsNil() {
        XCTAssertNil(AgentDateExpression(token: "next-week"))
        XCTAssertNil(AgentDateExpression(token: "2026-02-31"))
    }

    // MARK: - classifyAgentIntent

    private func classify(
        clarificationRequest: CloudClarificationRequestDTO? = nil,
        proposedSchedule: CloudProposedScheduleDTO? = nil,
        proposedScheduleUpdate: CloudProposedScheduleUpdateDTO? = nil,
        proposedRoutineUpdate: CloudProposedRoutineUpdateDTO? = nil,
        proposedReviewAction: CloudProposedReviewActionDTO? = nil,
        toolNames: [String] = []
    ) -> AgentIntent {
        classifyAgentIntent(
            clarificationRequest: clarificationRequest,
            proposedSchedule: proposedSchedule,
            proposedScheduleUpdate: proposedScheduleUpdate,
            proposedRoutineUpdate: proposedRoutineUpdate,
            proposedReviewAction: proposedReviewAction,
            toolNames: toolNames
        )
    }

    func test_classify_clarificationRequired() {
        let intent = classify(
            clarificationRequest: CloudClarificationRequestDTO(question: "몇 시에?", missingFields: nil, reason: nil)
        )
        XCTAssertEqual(intent, .clarificationRequired)
    }

    func test_classify_proposeSchedule() {
        let intent = classify(
            proposedSchedule: CloudProposedScheduleDTO(
                title: "치과", date: "tomorrow", startTime: "15:00", endTime: nil,
                isTask: false, note: nil, conflictTitle: nil, conflictCheckFailed: false
            )
        )
        XCTAssertEqual(intent, .proposeSchedule)
    }

    func test_classify_proposeScheduleUpdate() {
        let intent = classify(
            proposedScheduleUpdate: CloudProposedScheduleUpdateDTO(
                id: "a1", action: "complete", date: nil, startTime: nil, endTime: nil,
                title: "회의", version: 1, conflictTitle: nil, conflictCheckFailed: false
            )
        )
        XCTAssertEqual(intent, .proposeScheduleUpdate)
    }

    func test_classify_proposeRoutineUpdate() {
        let intent = classify(
            proposedRoutineUpdate: CloudProposedRoutineUpdateDTO(
                dailyReviewEnabled: true, dailyReviewTime: "22:00", newsBriefingEnabled: nil,
                newsBriefingTime: nil, planningPromptTime: nil, notificationsEnabled: nil
            )
        )
        XCTAssertEqual(intent, .proposeRoutineUpdate)
    }

    func test_classify_proposeReviewAction() {
        let intent = classify(
            proposedReviewAction: CloudProposedReviewActionDTO(date: "yesterday", reflection: "집중이 잘 됐다")
        )
        XCTAssertEqual(intent, .proposeReviewAction)
    }

    func test_classify_findFreeSlots() {
        XCTAssertEqual(classify(toolNames: ["find_free_slots"]), .findFreeSlots)
    }

    func test_classify_searchSchedules() {
        XCTAssertEqual(classify(toolNames: ["search_schedules"]), .searchSchedules)
    }

    func test_classify_answer_whenNothingStaged() {
        XCTAssertEqual(classify(), .answer)
    }

    func test_classify_priority_proposalWinsOverSearchToolName() {
        // A turn that both searches (to check for conflicts) AND proposes
        // classifies as the proposal -- the search was supporting work, not
        // the point of the turn (see classifyAgentIntent's doc comment).
        let intent = classify(
            proposedSchedule: CloudProposedScheduleDTO(
                title: "치과", date: "tomorrow", startTime: nil, endTime: nil,
                isTask: true, note: nil, conflictTitle: nil, conflictCheckFailed: false
            ),
            toolNames: ["search_schedules", "propose_schedule"]
        )
        XCTAssertEqual(intent, .proposeSchedule)
    }
}
