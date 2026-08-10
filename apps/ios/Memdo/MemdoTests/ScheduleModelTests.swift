import XCTest
@testable import Memdo

final class ScheduleModelTests: XCTestCase {
    private let calendar = ScheduleCalendar(
        id: "test-calendar",
        title: "테스트",
        purpose: "personal",
        provider: .memdo
    )

    func testMultiDayEventOccursOnEveryCoveredDay() throws {
        let systemCalendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 23)))
        let end = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 1)))
        let event = ScheduleDetail(
            scheduledDate: start,
            startAt: start,
            endAt: end,
            title: "출장",
            calendar: calendar
        )

        let coveredDay = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let lastCoveredDay = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 2)))
        let followingDay = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))

        XCTAssertTrue(event.occurs(on: coveredDay))
        XCTAssertTrue(event.occurs(on: lastCoveredDay))
        XCTAssertFalse(event.occurs(on: followingDay))
    }

    func testTaskDoesNotSpillIntoAnotherDay() throws {
        let systemCalendar = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 9)))
        let nextDay = try XCTUnwrap(systemCalendar.date(byAdding: .day, value: 1, to: day))
        let task = ScheduleDetail(
            scheduledDate: day,
            title: "할 일",
            kind: .task,
            calendar: calendar
        )

        XCTAssertTrue(task.occurs(on: day))
        XCTAssertFalse(task.occurs(on: nextDay))
    }

    func testSearchScopeTitlesStayUserFacing() {
        XCTAssertEqual(ScheduleSearchScope.all.title, "전체")
        XCTAssertEqual(ScheduleSearchScope.mine.title, "내 일정")
        XCTAssertEqual(ScheduleSearchScope.google.title, "Google")
    }
}
