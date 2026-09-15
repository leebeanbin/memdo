import XCTest
@testable import Memdo

final class NotificationSchedulerTests: XCTestCase {
    private let testCalendarEntity = ScheduleCalendar(
        id: "test-calendar",
        title: "테스트",
        purpose: "personal",
        provider: .memdo
    )

    // Fixed UTC Gregorian calendar so window-boundary math is deterministic
    // regardless of the machine/CI running these tests.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func now() throws -> Date {
        try XCTUnwrap(
            Calendar(identifier: .gregorian).date(from: DateComponents(
                timeZone: TimeZone(identifier: "UTC"),
                year: 2026, month: 8, day: 25, hour: 9, minute: 0
            ))
        )
    }

    private func event(
        id: UUID = UUID(),
        startAt: Date? = nil,
        endAt: Date? = nil,
        reminderOffsetMinutes: Int? = 30,
        status: ScheduleStatus = .planned
    ) -> ScheduleDetail {
        ScheduleDetail(
            id: id,
            scheduledDate: startAt ?? .now,
            startAt: startAt,
            endAt: endAt,
            title: "일정",
            status: status,
            reminderOffsetMinutes: reminderOffsetMinutes,
            calendar: testCalendarEntity
        )
    }

    func test_excludesPastFireTimes() throws {
        let now = try now()
        let past = now.addingTimeInterval(-3600)
        let schedule = event(startAt: past, endAt: past.addingTimeInterval(1800), reminderOffsetMinutes: 0)
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [schedule], now: now, calendar: utc
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_excludesFireTimesBeyondTheSevenDayWindow() throws {
        let now = try now()
        // windowEnd = startOfDay(now) + 7 days -- 9 days out is well past it.
        let farFuture = utc.date(byAdding: .day, value: 9, to: now)!
        let schedule = event(startAt: farFuture, reminderOffsetMinutes: 0)
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [schedule], now: now, calendar: utc
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_includesFireTimesWithinTheSevenDayWindow() throws {
        let now = try now()
        let inThreeDays = utc.date(byAdding: .day, value: 3, to: now)!
        let schedule = event(startAt: inThreeDays, reminderOffsetMinutes: 0)
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [schedule], now: now, calendar: utc
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].kind, .reminder)
    }

    func test_producesBothReminderAndEndCandidatesForOneEvent() throws {
        let now = try now()
        let start = now.addingTimeInterval(3600)
        let end = now.addingTimeInterval(7200)
        let schedule = event(startAt: start, endAt: end, reminderOffsetMinutes: 10)
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [schedule], now: now, calendar: utc
        )
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.contains { $0.kind == .reminder })
        XCTAssertTrue(candidates.contains { $0.kind == .end })
    }

    func test_noReminderCandidateWhenReminderOffsetIsNil() throws {
        let now = try now()
        let start = now.addingTimeInterval(3600)
        let end = now.addingTimeInterval(7200)
        let schedule = event(startAt: start, endAt: end, reminderOffsetMinutes: nil)
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [schedule], now: now, calendar: utc
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].kind, .end)
    }

    // R1-5: a task with only a due time (no startAt) previously never got a
    // reminder candidate at all -- reconciledNotificationCandidates required
    // schedule.startAt unconditionally. schedule.reminderAnchor now falls
    // back to dueAt for a task with no scheduled time.
    func test_dueOnlyTaskProducesAReminderCandidateAnchoredOnDueAt() throws {
        let now = try now()
        let due = now.addingTimeInterval(3600)
        let task = ScheduleDetail(
            scheduledDate: due,
            dueAt: due,
            title: "마감 있는 할 일",
            reminderOffsetMinutes: 10,
            kind: .task,
            calendar: testCalendarEntity
        )
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [task], now: now, calendar: utc
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].kind, .reminder)
        XCTAssertEqual(candidates[0].fireAt, due.addingTimeInterval(-600))
    }

    func test_taskWithNeitherStartNorDueHasNoReminderCandidate() throws {
        let now = try now()
        let task = ScheduleDetail(
            scheduledDate: now,
            title: "시간 없는 할 일",
            reminderOffsetMinutes: 10,
            kind: .task,
            calendar: testCalendarEntity
        )
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [task], now: now, calendar: utc
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_excludesDoneAndInactiveSchedules() throws {
        let now = try now()
        let start = now.addingTimeInterval(3600)
        let done = event(startAt: start, reminderOffsetMinutes: 0, status: .completed)
        let cancelled = event(startAt: start, reminderOffsetMinutes: 0, status: .cancelled)
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [done, cancelled], now: now, calendar: utc
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_sortsAscendingByFireTime() throws {
        let now = try now()
        let later = event(startAt: now.addingTimeInterval(7200), reminderOffsetMinutes: 0)
        let sooner = event(startAt: now.addingTimeInterval(3600), reminderOffsetMinutes: 0)
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [later, sooner], now: now, calendar: utc
        )
        XCTAssertEqual(candidates.map(\.scheduleID), [sooner.id, later.id])
    }

    func test_tieBreaksEqualFireTimesByScheduleIDString() throws {
        let now = try now()
        let sameFireAt = now.addingTimeInterval(3600)
        let idA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let idB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let scheduleB = event(id: idB, startAt: sameFireAt, reminderOffsetMinutes: 0)
        let scheduleA = event(id: idA, startAt: sameFireAt, reminderOffsetMinutes: 0)
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [scheduleB, scheduleA], now: now, calendar: utc
        )
        // "AAAA..." sorts before "BBBB..." as strings -- A must come first
        // regardless of input order, since fireAt is tied.
        XCTAssertEqual(candidates.map(\.scheduleID), [idA, idB])
    }

    func test_capsAtMaxCountKeepingOnlyTheNearestCandidates() throws {
        let now = try now()
        // 5 candidates at increasing distances, cap at 3 -- only the 3
        // soonest should survive, furthest 2 dropped.
        let schedules = (0..<5).map { i in
            event(startAt: now.addingTimeInterval(Double(3600 * (i + 1))), reminderOffsetMinutes: 0)
        }
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: schedules, now: now, maxCount: 3, calendar: utc
        )
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(candidates.map(\.scheduleID), schedules.prefix(3).map(\.id))
    }

    // MARK: - R0-3: reminderOffsetText must distinguish day counts, not
    // collapse every offset >=1440 minutes into "내일"

    func test_reminderOffsetText_minutesAndHours() {
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 0), "지금 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 30), "30분 후 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 60), "1시간 후 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 120), "2시간 후 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 90), "1시간 30분 후 시작해요")
    }

    func test_reminderOffsetText_distinctDayCounts_notAllTomorrow() {
        // The exact bug: every one of these used to return "내일 시작해요".
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 1440), "내일 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 2880), "2일 후 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 10080), "7일 후 시작해요")
    }

    func test_reminderOffsetText_nonExactDayOffsetRoundsDownToWholeDays() {
        // 1500 min = 1 day 1 hour -- still within the "내일" day, not a
        // third time unit.
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 1500), "내일 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 3000), "2일 후 시작해요")
    }
}
