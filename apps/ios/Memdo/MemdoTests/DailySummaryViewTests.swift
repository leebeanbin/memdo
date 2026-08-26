import XCTest
@testable import Memdo

final class DailySummaryViewTests: XCTestCase {
    private let calendar = ScheduleCalendar(
        id: "test-calendar",
        title: "테스트",
        purpose: "personal",
        provider: .memdo
    )

    func testSummaryTasksIncludesTimedEventsNotJustTaskKind() throws {
        let systemCalendar = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 26)))
        let morning = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 9)))

        let timedEvent = ScheduleDetail(
            scheduledDate: day,
            startAt: morning,
            title: "회의",
            kind: .event,
            calendar: calendar
        )
        let untimedTask = ScheduleDetail(
            scheduledDate: day,
            title: "할 일",
            kind: .task,
            calendar: calendar
        )

        let interval = DateInterval(
            start: systemCalendar.startOfDay(for: day),
            end: try XCTUnwrap(systemCalendar.date(byAdding: .day, value: 1, to: systemCalendar.startOfDay(for: day)))
        )

        let result = DailySummaryView.summaryTasks(
            from: [timedEvent, untimedTask],
            interval: interval,
            ascending: true
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.id == timedEvent.id })
        XCTAssertTrue(result.contains { $0.id == untimedTask.id })
    }

    func testSummaryTasksExcludesInactiveAndOutOfRangeItems() throws {
        let systemCalendar = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 26)))
        let nextDay = try XCTUnwrap(systemCalendar.date(byAdding: .day, value: 1, to: day))

        var cancelled = ScheduleDetail(scheduledDate: day, title: "취소됨", kind: .event, calendar: calendar)
        cancelled.status = .cancelled
        let tomorrow = ScheduleDetail(scheduledDate: nextDay, title: "내일 일정", kind: .event, calendar: calendar)
        let today = ScheduleDetail(scheduledDate: day, title: "오늘 일정", kind: .event, calendar: calendar)

        let interval = DateInterval(
            start: systemCalendar.startOfDay(for: day),
            end: systemCalendar.startOfDay(for: nextDay)
        )

        let result = DailySummaryView.summaryTasks(
            from: [cancelled, tomorrow, today],
            interval: interval,
            ascending: true
        )

        XCTAssertEqual(result.map(\.id), [today.id])
    }
}
