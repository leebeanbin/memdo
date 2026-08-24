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
}
