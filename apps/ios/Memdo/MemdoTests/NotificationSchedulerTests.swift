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
        XCTAssertEqual(candidates[0].kind, .reminder(offsetMinutes: 0))
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
        XCTAssertTrue(candidates.contains { $0.kind == .reminder(offsetMinutes: 10) })
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
        XCTAssertEqual(candidates[0].kind, .reminder(offsetMinutes: 10))
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

    // MARK: - R0-3/R1-6: reminderOffsetText must distinguish day counts, not
    // collapse every offset >=1440 minutes into "내일", and must read
    // differently for a due-anchored reminder ("마감이에요") than a
    // start-anchored one ("시작해요").

    private let anyStart = ScheduleDetail.ReminderAnchor.start(Date())
    private let anyDue = ScheduleDetail.ReminderAnchor.due(Date())

    func test_reminderOffsetText_minutesAndHours() {
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 0, anchor: anyStart), "지금 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 30, anchor: anyStart), "30분 후 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 60, anchor: anyStart), "1시간 후 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 120, anchor: anyStart), "2시간 후 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 90, anchor: anyStart), "1시간 30분 후 시작해요")
    }

    func test_reminderOffsetText_distinctDayCounts_notAllTomorrow() {
        // The exact bug: every one of these used to return "내일 시작해요".
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 1440, anchor: anyStart), "내일 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 2880, anchor: anyStart), "2일 후 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 10080, anchor: anyStart), "7일 후 시작해요")
    }

    func test_reminderOffsetText_nonExactDayOffsetRoundsDownToWholeDays() {
        // 1500 min = 1 day 1 hour -- still within the "내일" day, not a
        // third time unit.
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 1500, anchor: anyStart), "내일 시작해요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 3000, anchor: anyStart), "2일 후 시작해요")
    }

    func test_twoDayReminderTextIsNotTomorrow() {
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 2880, anchor: anyStart), "2일 후 시작해요")
        XCTAssertNotEqual(NotificationScheduler.reminderOffsetText(offset: 2880, anchor: anyStart), "내일 시작해요")
    }

    func test_sevenDayReminderText() {
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 10080, anchor: anyStart), "7일 후 시작해요")
    }

    func test_reminderOffsetText_dueAnchorUsesMagamVerb() {
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 0, anchor: anyDue), "지금 마감이에요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 30, anchor: anyDue), "30분 후 마감이에요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 120, anchor: anyDue), "2시간 후 마감이에요")
        XCTAssertEqual(NotificationScheduler.reminderOffsetText(offset: 2880, anchor: anyDue), "2일 후 마감이에요")
    }

    // MARK: - R1-6: multi-reminder candidate generation

    func test_producesTwoReminderCandidatesForOneSchedule() throws {
        let now = try now()
        let start = now.addingTimeInterval(7200)
        let schedule = ScheduleDetail(
            scheduledDate: start, startAt: start, endAt: start.addingTimeInterval(1800),
            title: "일정", reminderOffsetsMinutes: [10, 30], calendar: testCalendarEntity
        )
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [schedule], now: now, calendar: utc
        )
        let reminderCandidates = candidates.filter { $0.kind != .end }
        XCTAssertEqual(reminderCandidates.count, 2)
        XCTAssertEqual(Set(reminderCandidates.map(\.fireAt)), [
            start.addingTimeInterval(-600), start.addingTimeInterval(-1800)
        ])
    }

    func test_eachReminderGetsUniqueIdentifier() throws {
        let now = try now()
        let start = now.addingTimeInterval(7200)
        let schedule = ScheduleDetail(
            scheduledDate: start, startAt: start, title: "일정",
            reminderOffsetsMinutes: [10, 30, 60], calendar: testCalendarEntity
        )
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [schedule], now: now, calendar: utc
        )
        let offsets: [Int] = candidates.compactMap {
            if case .reminder(let offsetMinutes) = $0.kind { return offsetMinutes }
            return nil
        }
        XCTAssertEqual(Set(offsets), [10, 30, 60])
    }

    func test_taskUsesStartAtAsReminderAnchor() throws {
        let now = try now()
        let start = now.addingTimeInterval(3600)
        let due = start.addingTimeInterval(7200)
        let task = ScheduleDetail(
            scheduledDate: start, startAt: start, endAt: start.addingTimeInterval(1800), dueAt: due,
            title: "할 일", reminderOffsetsMinutes: [10], kind: .task, calendar: testCalendarEntity
        )
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [task], now: now, calendar: utc
        )
        let reminder = try XCTUnwrap(candidates.first { $0.kind != .end })
        XCTAssertEqual(reminder.fireAt, start.addingTimeInterval(-600))
    }

    func test_taskFallsBackToDueAt() throws {
        let now = try now()
        let due = now.addingTimeInterval(3600)
        let task = ScheduleDetail(
            scheduledDate: due, dueAt: due, title: "할 일",
            reminderOffsetsMinutes: [10], kind: .task, calendar: testCalendarEntity
        )
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [task], now: now, calendar: utc
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].fireAt, due.addingTimeInterval(-600))
    }

    func test_taskWithoutStartOrDueProducesNoReminder() throws {
        let now = try now()
        let task = ScheduleDetail(
            scheduledDate: now, title: "할 일", reminderOffsetsMinutes: [10], kind: .task,
            calendar: testCalendarEntity
        )
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [task], now: now, calendar: utc
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_multipleRemindersStillRespectSevenDayWindow() throws {
        let now = try now()
        // windowEnd = startOfDay(now) + 7 days.
        let start = utc.date(byAdding: .day, value: 9, to: now)!
        let schedule = ScheduleDetail(
            scheduledDate: start, startAt: start, title: "일정",
            reminderOffsetsMinutes: [10, 30], calendar: testCalendarEntity
        )
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [schedule], now: now, calendar: utc
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_multipleRemindersAndEndNotificationsShare48Cap() throws {
        let now = try now()
        // 3 reminders + 1 end candidate per schedule -- 13 schedules would
        // produce 52 candidates uncapped, well past the 48 cap.
        let schedules = (0..<13).map { i -> ScheduleDetail in
            let start = now.addingTimeInterval(Double(3600 * (i + 1)))
            return ScheduleDetail(
                scheduledDate: start, startAt: start, endAt: start.addingTimeInterval(1800),
                title: "일정", reminderOffsetsMinutes: [5, 10, 30], calendar: testCalendarEntity
            )
        }
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: schedules, now: now, calendar: utc
        )
        XCTAssertEqual(candidates.count, 48)
    }

    func test_completedScheduleProducesNoReminderCandidates() throws {
        let now = try now()
        let start = now.addingTimeInterval(3600)
        let schedule = ScheduleDetail(
            scheduledDate: start, startAt: start, title: "일정", status: .completed,
            reminderOffsetsMinutes: [10, 30], calendar: testCalendarEntity
        )
        let candidates = NotificationScheduler.reconciledNotificationCandidates(
            schedules: [schedule], now: now, calendar: utc
        )
        XCTAssertTrue(candidates.isEmpty)
    }
}
