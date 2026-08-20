import XCTest
import UIKit
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

    func testBriefingKeepsDiscoveryBesideFollowedTopics() {
        func item(_ id: String, _ category: BriefingFeedCategory) -> BriefingRepository.FetchedItem {
            .init(
                id: id,
                title: id,
                summary: "",
                url: nil,
                sourceName: "test",
                category: category,
                publishedAt: nil,
                matchedKeyword: nil
            )
        }

        let items = [
            item("e1", .economy), item("e2", .economy), item("e3", .economy), item("e4", .economy),
            item("t1", .tech), item("w1", .world)
        ]
        let result = TodayBriefingSection.curatedItems(items, selectedCategories: [.economy])

        XCTAssertEqual(result.map(\.id), ["e1", "e2", "e3", "t1", "w1"])
    }

    func testPretendardFacesAreBundled() {
        // One assertion per embedded static face (Regular/SemiBold/Bold) --
        // MemdoTypography references each by its own PostScript name (see
        // MemdoTheme.swift), so a typo or a missing UIAppFonts entry for any
        // one of them would silently fall back to the system font instead of
        // failing loudly, which is exactly what this guards against.
        XCTAssertNotNil(UIFont(name: "Pretendard-Regular", size: 17))
        XCTAssertNotNil(UIFont(name: "Pretendard-SemiBold", size: 17))
        XCTAssertNotNil(UIFont(name: "Pretendard-Bold", size: 17))
    }

    func testAgentPromptsYAMLLoadsAndResolvesEveryContext() {
        // Exercises the actual bundled AgentPrompts.yml through Yams, not a
        // hand-written fixture -- a YAML syntax error or a schema mismatch
        // against AgentPrompts.swift's Decodable types would otherwise only
        // surface as a runtime fatalError() the first time a user opened the
        // Agent tab.
        XCTAssertFalse(AgentPrompts.onDeviceInstructions.isEmpty)
        XCTAssertFalse(AgentPrompts.briefingHeadlineInstructions.isEmpty)
        XCTAssertFalse(AgentPrompts.briefingCleanupInstructions.isEmpty)

        for context: AgentContext in [.today, .calendar, .settings, .todaySummary, .weekReview, .monthReview] {
            for hasSchedulesToday in [true, false] {
                let actions = AgentPrompts.quickActions(for: context, hasSchedulesToday: hasSchedulesToday)
                XCTAssertEqual(actions.count, 3, "\(context) (hasSchedulesToday: \(hasSchedulesToday))")
                for (label, prompt) in actions {
                    XCTAssertFalse(label.isEmpty)
                    XCTAssertFalse(prompt.isEmpty)
                    XCTAssertFalse(prompt.contains("{context}"), "unsubstituted placeholder in: \(prompt)")
                }
            }
        }

        // The review contexts share one prompt set with `{context}`
        // substitution -- confirm it actually varies per context rather than
        // silently no-op'ing the replace.
        let weekPrompts = AgentPrompts.quickActions(for: .weekReview, hasSchedulesToday: true)
        let monthPrompts = AgentPrompts.quickActions(for: .monthReview, hasSchedulesToday: true)
        XCTAssertNotEqual(weekPrompts.map(\.1), monthPrompts.map(\.1))
    }
}
