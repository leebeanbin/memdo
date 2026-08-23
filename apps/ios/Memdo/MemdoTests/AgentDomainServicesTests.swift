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
}
