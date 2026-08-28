// Agent Domain Fixture Contract: v1
import XCTest
@testable import Memdo

final class AgentDomainServicesTests: XCTestCase {
    // Fixed reference day, plain UTC clock times -- FreeSlotService/
    // ConflictService do no timezone math of their own (that's the
    // caller's job), so bare UTC instants are fine here.
    private func at(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var components = DateComponents()
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = 2026; components.month = 8; components.day = 16
        components.hour = parts[0]; components.minute = parts[1]
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func range(_ startHHmm: String, _ endHHmm: String) -> AgentTimeRange {
        AgentTimeRange(start: at(startHHmm), end: at(endHHmm))
    }

    private func assertSlots(_ actual: [AgentTimeRange], _ expected: [(String, String)],
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (slot, exp) in zip(actual, expected) {
            XCTAssertEqual(slot.start, at(exp.0), file: file, line: line)
            XCTAssertEqual(slot.end, at(exp.1), file: file, line: line)
        }
    }

    private let hour: TimeInterval = 3600

    // MARK: - free-slot/*

    func test_freeSlot_noBusy() {
        let slots = FreeSlotService.freeSlots(busy: [], windowStart: at("09:00"), windowEnd: at("18:00"), duration: hour)
        assertSlots(slots, [("09:00", "10:00")])
    }

    func test_freeSlot_singleGapFits() {
        let slots = FreeSlotService.freeSlots(busy: [range("10:00", "11:00")], windowStart: at("09:00"), windowEnd: at("18:00"), duration: hour)
        assertSlots(slots, [("09:00", "10:00"), ("11:00", "12:00")])
    }

    func test_freeSlot_gapTooSmall() {
        let busy = [range("09:30", "10:30"), range("10:45", "18:00")]
        let slots = FreeSlotService.freeSlots(busy: busy, windowStart: at("09:00"), windowEnd: at("18:00"), duration: hour)
        XCTAssertTrue(slots.isEmpty)
    }

    func test_freeSlot_backToBackBusy() {
        let busy = [range("09:00", "12:00"), range("12:00", "15:00")]
        let slots = FreeSlotService.freeSlots(busy: busy, windowStart: at("09:00"), windowEnd: at("18:00"), duration: hour)
        assertSlots(slots, [("15:00", "16:00")])
    }

    func test_freeSlot_moreThanMaxResults() {
        let busy = [
            range("10:00", "10:05"), range("11:05", "11:10"), range("12:10", "12:15"),
            range("13:15", "13:20"), range("14:20", "14:25"),
        ]
        let slots = FreeSlotService.freeSlots(busy: busy, windowStart: at("09:00"), windowEnd: at("18:00"), duration: hour)
        assertSlots(slots, [("09:00", "10:00"), ("10:05", "11:05"), ("11:10", "12:10")])
    }

    func test_freeSlot_invalidBusyRange() {
        // 10:00-09:00 is reversed, 11:00-11:00 has zero length -- both ignored.
        let busy = [range("10:00", "09:00"), range("11:00", "11:00")]
        let slots = FreeSlotService.freeSlots(busy: busy, windowStart: at("09:00"), windowEnd: at("18:00"), duration: hour)
        assertSlots(slots, [("09:00", "10:00")])
    }

    func test_freeSlot_invalidWindow() {
        let slots = FreeSlotService.freeSlots(busy: [], windowStart: at("18:00"), windowEnd: at("09:00"), duration: hour)
        XCTAssertTrue(slots.isEmpty)
    }

    func test_freeSlot_busyAfterWindow() {
        // Without clipping this would be misread as "the window is entirely
        // free" and produce a candidate extending past windowEnd.
        let slots = FreeSlotService.freeSlots(busy: [range("12:00", "13:00")], windowStart: at("09:00"), windowEnd: at("10:00"), duration: 2 * hour)
        XCTAssertTrue(slots.isEmpty)
    }

    func test_freeSlot_busySpansWindowStart() {
        let slots = FreeSlotService.freeSlots(busy: [range("08:00", "10:00")], windowStart: at("09:00"), windowEnd: at("12:00"), duration: hour)
        assertSlots(slots, [("10:00", "11:00")])
    }

    func test_freeSlotsInWindow_returnsEmptyForNonPositiveDuration() {
        let slots = FreeSlotService.freeSlots(busy: [], windowStart: at("09:00"), windowEnd: at("18:00"), duration: 0)
        XCTAssertTrue(slots.isEmpty)
    }

    func test_freeSlotsInWindow_returnsEmptyForNonPositiveMaxResults() {
        let slots = FreeSlotService.freeSlots(busy: [], windowStart: at("09:00"), windowEnd: at("18:00"), duration: hour, maxResults: 0)
        XCTAssertTrue(slots.isEmpty)
    }

    // MARK: - fullFreeExtents/* (availability-query contract, "how free am
    // I" -- as opposed to freeSlots' duration-constrained candidate-slot
    // contract above. Found during founder dogfooding: an empty day used to
    // answer a plain availability question with a single arbitrary
    // duration-sized slot instead of the whole open window.)

    func test_fullFreeExtents_emptyDayReturnsWholeWindow() {
        let extents = FreeSlotService.fullFreeExtents(busy: [], windowStart: at("08:00"), windowEnd: at("22:00"))
        assertSlots(extents, [("08:00", "22:00")])
    }

    func test_fullFreeExtents_oneEventSplitsTheDay() {
        let extents = FreeSlotService.fullFreeExtents(busy: [range("12:00", "13:00")], windowStart: at("08:00"), windowEnd: at("22:00"))
        assertSlots(extents, [("08:00", "12:00"), ("13:00", "22:00")])
    }

    func test_fullFreeExtents_multipleEvents() {
        let busy = [range("09:00", "10:00"), range("13:00", "14:00"), range("17:00", "18:00")]
        let extents = FreeSlotService.fullFreeExtents(busy: busy, windowStart: at("08:00"), windowEnd: at("22:00"))
        assertSlots(extents, [("08:00", "09:00"), ("10:00", "13:00"), ("14:00", "17:00"), ("18:00", "22:00")])
    }

    func test_fullFreeExtents_adjacentEventsProduceNoGapBetweenThem() {
        let busy = [range("09:00", "12:00"), range("12:00", "15:00")]
        let extents = FreeSlotService.fullFreeExtents(busy: busy, windowStart: at("08:00"), windowEnd: at("18:00"))
        assertSlots(extents, [("08:00", "09:00"), ("15:00", "18:00")])
    }

    func test_fullFreeExtents_overlappingEventsMergeIntoOneBusyBlock() {
        let busy = [range("09:00", "12:00"), range("11:00", "14:00")]
        let extents = FreeSlotService.fullFreeExtents(busy: busy, windowStart: at("08:00"), windowEnd: at("18:00"))
        assertSlots(extents, [("08:00", "09:00"), ("14:00", "18:00")])
    }

    func test_fullFreeExtents_fullyBookedWindowReturnsEmpty() {
        let extents = FreeSlotService.fullFreeExtents(busy: [range("08:00", "22:00")], windowStart: at("08:00"), windowEnd: at("22:00"))
        XCTAssertTrue(extents.isEmpty)
    }

    func test_fullFreeExtents_invalidWindowReturnsEmpty() {
        let extents = FreeSlotService.fullFreeExtents(busy: [], windowStart: at("18:00"), windowEnd: at("09:00"))
        XCTAssertTrue(extents.isEmpty)
    }

    func test_fullFreeExtents_busyOutsideWindowIsClippedAway() {
        let extents = FreeSlotService.fullFreeExtents(busy: [range("12:00", "13:00")], windowStart: at("08:00"), windowEnd: at("10:00"))
        assertSlots(extents, [("08:00", "10:00")])
    }

    func test_fullFreeExtents_busyStraddlingWindowEdgeIsTrimmed() {
        let extents = FreeSlotService.fullFreeExtents(busy: [range("07:00", "09:00")], windowStart: at("08:00"), windowEnd: at("12:00"))
        assertSlots(extents, [("09:00", "12:00")])
    }

    // MARK: - conflict/*

    private func candidate(_ id: String, _ title: String, _ startHHmm: String, _ endHHmm: String) -> ConflictService.ExistingItem {
        .init(id: id, title: title, startAt: at(startHHmm), endAt: at(endHHmm))
    }

    func test_conflict_overlap() {
        let existing = [candidate("e1", "팀 회의", "10:30", "11:30")]
        let result = ConflictService.conflict(for: range("10:00", "11:00"), in: existing)
        XCTAssertEqual(result?.id, "e1")
    }

    func test_conflict_adjacentNoOverlap() {
        // Touching boundaries are not a conflict.
        let existing = [candidate("e1", "팀 회의", "11:00", "12:00")]
        let result = ConflictService.conflict(for: range("10:00", "11:00"), in: existing)
        XCTAssertNil(result)
    }

    func test_conflict_excludesSelf() {
        let existing = [candidate("a1", "팀 회의", "10:00", "11:00")]
        let result = ConflictService.conflict(for: range("10:00", "11:00"), excludingId: "a1", in: existing)
        XCTAssertNil(result)
    }

    func test_conflict_firstMatch() {
        // A and B both overlap the candidate; A is first in `existing`'s
        // input order -- findConflict returns the first match in that
        // order, not necessarily the chronologically earliest one.
        let existing = [candidate("a", "A", "10:30", "11:00"), candidate("b", "B", "11:00", "11:30")]
        let result = ConflictService.conflict(for: range("10:00", "12:00"), in: existing)
        XCTAssertEqual(result?.id, "a")
    }

    func test_conflict_noTime() {
        // Boundary/adaptation fixture: unlike the backend (where
        // ConflictCandidate.start/end are non-optional and a no-time row is
        // filtered before ever reaching conflict-service.ts), iOS's
        // ConflictService.ExistingItem keeps startAt/endAt optional and
        // skips nil ones internally -- same result, different layer.
        let existing = [ConflictService.ExistingItem(id: "task-1", title: "할 일", startAt: nil, endAt: nil)]
        let result = ConflictService.conflict(for: range("10:00", "11:00"), in: existing)
        XCTAssertNil(result)
    }

    // MARK: - conflictRevalidationDecision (Issue C-04)
    //
    // confirmProposal(_:)/confirmScheduleUpdateProposal() are private View
    // methods with no meaningful way to drive them in isolation from
    // XCTest, so "does a second tap actually mutate" is verified here at
    // the decision-function level instead: both call sites route every
    // confirm through conflictRevalidationDecision, so two consecutive
    // calls (first with the stale staged value, second with staged
    // manually advanced to what the first call's .refresh produced) is
    // exactly the "tap, see refreshed card, tap again" sequence, without
    // needing to instantiate the View.

    private let snapA = AgentConflictSnapshot(id: "a", title: "회의")
    private let snapB = AgentConflictSnapshot(id: "b", title: "다른 일정")
    // Same title as snapA, different id -- the scenario that motivated
    // comparing by id instead of title (staged item deleted, a new one
    // with the same title took its place before confirm).
    private let snapAPrimeTitle = AgentConflictSnapshot(id: "b", title: "회의")

    func test_conflictRevalidation_noneToNone_proceeds() {
        XCTAssertEqual(conflictRevalidationDecision(staged: nil, fresh: nil), .proceed)
    }

    func test_conflictRevalidation_sameIdToSameId_proceeds() {
        XCTAssertEqual(conflictRevalidationDecision(staged: snapA, fresh: snapA), .proceed)
    }

    func test_conflictRevalidation_conflictResolved_proceedsWithoutReapproval() {
        // Benign: risk went down, not up -- no re-approval required.
        XCTAssertEqual(conflictRevalidationDecision(staged: snapA, fresh: nil), .proceed)
    }

    func test_conflictRevalidation_noneToNewConflict_refreshesWithoutMutating() {
        XCTAssertEqual(conflictRevalidationDecision(staged: nil, fresh: snapB), .refresh(snapB))
    }

    func test_conflictRevalidation_differentId_refreshesWithoutMutating() {
        XCTAssertEqual(conflictRevalidationDecision(staged: snapA, fresh: snapB), .refresh(snapB))
    }

    func test_conflictRevalidation_sameTitleDifferentId_isTreatedAsChanged() {
        // The scenario Issue C-04's identity-over-title fix targets directly:
        // title comparison alone would have called this "unchanged".
        XCTAssertEqual(conflictRevalidationDecision(staged: snapA, fresh: snapAPrimeTitle), .refresh(snapAPrimeTitle))
    }

    func test_conflictRevalidation_refreshThenSecondTap_proceeds() {
        // First tap: staged (nil) doesn't match fresh (B) -> refresh, no mutation.
        let firstTap = conflictRevalidationDecision(staged: nil, fresh: snapB)
        guard case .refresh(let refreshed) = firstTap else {
            return XCTFail("expected .refresh, got \(firstTap)")
        }
        XCTAssertEqual(refreshed, snapB)

        // Card now shows `refreshed` as the staged conflict (proposal.conflict
        // = refreshed, exactly as confirmProposal(_:)/confirmScheduleUpdateProposal()
        // do on .refresh). Second tap, conflict state unchanged since the refresh
        // -> proceeds, which is where the real save/move call happens.
        let secondTap = conflictRevalidationDecision(staged: refreshed, fresh: snapB)
        XCTAssertEqual(secondTap, .proceed)
    }

    // MARK: - stage-schedule/* (Epic D-2)
    //
    // Unlike free-slot/conflict above, these go through stageScheduleProposal/
    // stageScheduleUpdate's own date resolution (AgentDateExpression), which
    // for "today" resolves against the real wall-clock date, not the fixed
    // 2026-08-16 reference day `at()`/`candidate()` use -- so conflict
    // fixtures here are built relative to `Date.now` via todayCandidate(),
    // not the fixed-day candidate() helper.

    private func todayCandidate(_ id: String, _ title: String, _ startHHmm: String, _ endHHmm: String) -> ConflictService.ExistingItem {
        let today = Calendar.current.startOfDay(for: .now)
        return .init(
            id: id, title: title,
            startAt: parseAgentTime(startHHmm, on: today),
            endAt: parseAgentTime(endHHmm, on: today)
        )
    }

    func test_stageSchedule_validCreate_noConflict() {
        let result = stageScheduleProposal(
            title: "치과", date: "today", startTime: "15:00", endTime: "", isTask: false, note: "",
            existing: []
        )
        guard case .staged(let draft, let conflict, let conflictCheckFailed) = result else {
            return XCTFail("expected .staged, got \(result)")
        }
        XCTAssertEqual(draft.title, "치과")
        XCTAssertNil(conflict)
        XCTAssertFalse(conflictCheckFailed)
    }

    func test_stageSchedule_validCreate_withConflict() {
        let existing = [todayCandidate("e1", "팀 회의", "15:00", "16:00")]
        let result = stageScheduleProposal(
            title: "치과", date: "today", startTime: "15:00", endTime: "16:00", isTask: false, note: "",
            existing: existing
        )
        guard case .staged(_, let conflict, _) = result else {
            return XCTFail("expected .staged, got \(result)")
        }
        XCTAssertEqual(conflict?.id, "e1")
    }

    func test_stageSchedule_invalidDate() {
        let result = stageScheduleProposal(
            title: "치과", date: "banana", startTime: "15:00", endTime: "", isTask: false, note: "",
            existing: []
        )
        XCTAssertEqual(result, .invalidDate)
    }

    func test_stageSchedule_task_hasNoConflict() {
        // A task has no resolvedInterval() -- nothing to conflict-check,
        // regardless of what's in `existing`.
        let existing = [todayCandidate("e1", "팀 회의", "15:00", "16:00")]
        let result = stageScheduleProposal(
            title: "장보기", date: "today", startTime: "", endTime: "", isTask: true, note: "",
            existing: existing
        )
        guard case .staged(let draft, let conflict, _) = result else {
            return XCTFail("expected .staged, got \(result)")
        }
        XCTAssertTrue(draft.isTask)
        XCTAssertNil(conflict)
    }

    // MARK: - stage-update/* (Epic D-2)

    func test_stageUpdate_complete_noDateNeeded() {
        let result = stageScheduleUpdate(
            id: "id-1", title: "팀 회의", action: .complete,
            dateString: nil, startTimeString: nil, endTimeString: nil,
            existing: []
        )
        guard case .staged(let id, let action, _, _, _, _, let conflict, _) = result else {
            return XCTFail("expected .staged, got \(result)")
        }
        XCTAssertEqual(id, "id-1")
        XCTAssertEqual(action, .complete)
        XCTAssertNil(conflict)
    }

    func test_stageUpdate_reschedule_withConflict() {
        let existing = [todayCandidate("e2", "점심 약속", "12:00", "13:00")]
        let result = stageScheduleUpdate(
            id: "id-1", title: "팀 회의", action: .reschedule,
            dateString: "today", startTimeString: "12:30", endTimeString: "13:00",
            existing: existing
        )
        guard case .staged(_, _, _, _, _, _, let conflict, _) = result else {
            return XCTFail("expected .staged, got \(result)")
        }
        XCTAssertEqual(conflict?.id, "e2")
    }

    func test_stageUpdate_reschedule_excludesSelf() {
        // Issue C-04 Acceptance Criteria #8 -- the target's own row must
        // never read as a self-conflict when moved onto its own time.
        let existing = [todayCandidate("id-1", "팀 회의", "09:00", "10:00")]
        let result = stageScheduleUpdate(
            id: "id-1", title: "팀 회의", action: .reschedule,
            dateString: "today", startTimeString: "09:00", endTimeString: "10:00",
            existing: existing
        )
        guard case .staged(_, _, _, _, _, _, let conflict, _) = result else {
            return XCTFail("expected .staged, got \(result)")
        }
        XCTAssertNil(conflict)
    }

    func test_stageUpdate_reschedule_missingDate_isInvalid() {
        // The bug D-2 closes: previously only on-device enforced this --
        // cloud ingestion's older validation would have let a dateless
        // reschedule through since `nil` short-circuited to "valid".
        let result = stageScheduleUpdate(
            id: "id-1", title: "팀 회의", action: .reschedule,
            dateString: nil, startTimeString: nil, endTimeString: nil,
            existing: []
        )
        XCTAssertEqual(result, .invalidDate)
    }

    func test_stageUpdate_reschedule_unparseableDate_isInvalid() {
        let result = stageScheduleUpdate(
            id: "id-1", title: "팀 회의", action: .reschedule,
            dateString: "banana", startTimeString: "09:00", endTimeString: "10:00",
            existing: []
        )
        XCTAssertEqual(result, .invalidDate)
    }

    func test_stageUpdate_delete_noDateNeeded() {
        let result = stageScheduleUpdate(
            id: "id-1", title: "팀 회의", action: .delete,
            dateString: nil, startTimeString: nil, endTimeString: nil,
            existing: []
        )
        guard case .staged(_, let action, _, _, _, _, _, _) = result else {
            return XCTFail("expected .staged, got \(result)")
        }
        XCTAssertEqual(action, .delete)
    }

    // MARK: - applyRoutineUpdate (Epic I)

    private func basePreferences() -> UserPreferences {
        UserPreferences(
            timezone: "Asia/Seoul",
            widgetStyle: "default",
            defaultMood: nil,
            hideWidgetContent: false,
            notificationsEnabled: true,
            planningPromptTime: "07:30",
            quietHoursStart: nil,
            quietHoursEnd: nil,
            calendarFilter: [],
            dailyReviewEnabled: false,
            dailyReviewTime: "21:00",
            dailyReviewDays: ["MO", "TU", "WE", "TH", "FR"],
            dailyReviewIncludeReflection: true,
            newsBriefingEnabled: false,
            newsBriefingTime: "08:00",
            newsBriefingDays: UserPreferences.allWeekdays
        )
    }

    func test_applyRoutineUpdate_onlyChangesPresentFields() {
        let base = basePreferences()
        let proposal = CloudProposedRoutineUpdateDTO(
            dailyReviewEnabled: true,
            dailyReviewTime: "22:00",
            newsBriefingEnabled: nil,
            newsBriefingTime: nil,
            planningPromptTime: nil,
            notificationsEnabled: nil
        )
        let updated = applyRoutineUpdate(proposal, to: base)

        XCTAssertEqual(updated.dailyReviewEnabled, true)
        XCTAssertEqual(updated.dailyReviewTime, "22:00")
        // Untouched fields, including ones the tool can never propose --
        // dailyReviewDays/dailyReviewIncludeReflection aren't in
        // CloudProposedRoutineUpdateDTO at all.
        XCTAssertEqual(updated.newsBriefingEnabled, base.newsBriefingEnabled)
        XCTAssertEqual(updated.newsBriefingTime, base.newsBriefingTime)
        XCTAssertEqual(updated.planningPromptTime, base.planningPromptTime)
        XCTAssertEqual(updated.notificationsEnabled, base.notificationsEnabled)
        XCTAssertEqual(updated.dailyReviewDays, base.dailyReviewDays)
        XCTAssertEqual(updated.dailyReviewIncludeReflection, base.dailyReviewIncludeReflection)
        XCTAssertEqual(updated.newsBriefingDays, base.newsBriefingDays)
        XCTAssertEqual(updated.timezone, base.timezone)
    }

    func test_applyRoutineUpdate_allFieldsAbsent_isANoOp() {
        let base = basePreferences()
        let proposal = CloudProposedRoutineUpdateDTO(
            dailyReviewEnabled: nil, dailyReviewTime: nil,
            newsBriefingEnabled: nil, newsBriefingTime: nil,
            planningPromptTime: nil, notificationsEnabled: nil
        )
        XCTAssertEqual(applyRoutineUpdate(proposal, to: base), base)
    }
}
