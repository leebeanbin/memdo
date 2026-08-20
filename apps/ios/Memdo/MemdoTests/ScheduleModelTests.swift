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

    func testScheduleColorResolvesCorrectDynamicRGBForLightAndDark() {
        // NotificationScheduler's notification-attachment thumbnail derives
        // its UIColor from this (UIColor(color.swiftUIColor)) rather than
        // keeping its own copy of these six dynamic light/dark RGB pairs --
        // this pins that the Color -> UIColor round trip actually preserves
        // the correct per-appearance value instead of silently collapsing
        // to one fixed color.
        let uiColor = UIColor(ScheduleColor.coral.swiftUIColor)

        let light = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        light.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        XCTAssertEqual(lr, 0.95, accuracy: 0.01)
        XCTAssertEqual(lg, 0.36, accuracy: 0.01)
        XCTAssertEqual(lb, 0.29, accuracy: 0.01)

        let dark = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        dark.getRed(&dr, green: &dg, blue: &db, alpha: &da)
        XCTAssertEqual(dr, 1.00, accuracy: 0.01)
        XCTAssertEqual(dg, 0.60, accuracy: 0.01)
        XCTAssertEqual(db, 0.55, accuracy: 0.01)
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

    @MainActor
    func testAgentScheduleUpdateProposalStateTransitions() {
        // propose_schedule_update's state class had no View reading it for a
        // while (see AssistantView.swift's messageList) -- this pins the
        // state transitions ProposedScheduleUpdateCard now renders from,
        // independent of the view layer.
        let proposal = AgentScheduleUpdateProposal()
        XCTAssertFalse(proposal.isPending)

        proposal.propose(
            id: "abc-123",
            action: "reschedule",
            title: "테스트 일정",
            dateString: "tomorrow",
            startTimeString: "09:00",
            endTimeString: "10:00",
            conflictTitle: "다른 일정",
            conflictCheckFailed: false
        )

        XCTAssertTrue(proposal.isPending)
        XCTAssertEqual(proposal.displayActionLabel, "일정 변경")
        XCTAssertEqual(proposal.displayDate, "내일")
        XCTAssertEqual(proposal.conflictTitle, "다른 일정")

        proposal.clear()
        XCTAssertFalse(proposal.isPending)
        XCTAssertNil(proposal.action)
        XCTAssertNil(proposal.conflictTitle)
    }

    @MainActor
    func testAgentScheduleUpdateProposalActionLabels() {
        let proposal = AgentScheduleUpdateProposal()
        let expected: [(String, String)] = [
            ("complete", "완료 처리"),
            ("reschedule", "일정 변경"),
            ("delete", "삭제"),
            ("unknown", "변경")
        ]
        for (action, label) in expected {
            proposal.propose(
                id: "x", action: action, title: "t",
                dateString: nil, startTimeString: nil, endTimeString: nil,
                conflictTitle: nil, conflictCheckFailed: false
            )
            XCTAssertEqual(proposal.displayActionLabel, label, action)
        }
    }

    func testAgentMarkdownTextClassifiesListLinesAndStripsTheirMarker() {
        // Reproduces a real model response reported as looking "raw" --
        // AttributedString(markdown:) with .inlineOnlyPreservingWhitespace
        // parses **bold** correctly but has no concept of list markers, so
        // "* **제안 일정**: ..." rendered with a literal leading asterisk.
        let text = """
            오늘의 일정을 알려줄게.

            * **제안 일정**: 오늘 일정을 제안해줄게.
            * **공백 시간 찾기**: 오늘의 공백 시간을 찾아줄게.
            - 하이픈도 목록으로 인식돼야 해
            일반 문단은 그대로 유지돼야 해
            """
        let lines = AgentMarkdownText.lines(for: text)

        XCTAssertEqual(lines[0].content, "오늘의 일정을 알려줄게.")
        XCTAssertFalse(lines[0].isListItem)

        XCTAssertEqual(lines[1].content, "")

        XCTAssertTrue(lines[2].isListItem)
        // The list marker ("* ") is stripped here; the bold markup that
        // remains ("**제안 일정**") is inline markdown, parsed separately by
        // inlineAttributed() below -- not this classification step's job.
        XCTAssertEqual(lines[2].content, "**제안 일정**: 오늘 일정을 제안해줄게.")

        XCTAssertTrue(lines[3].isListItem)

        XCTAssertTrue(lines[4].isListItem, "a hyphen marker is a list item too")
        XCTAssertEqual(lines[4].content, "하이픈도 목록으로 인식돼야 해")

        XCTAssertFalse(lines[5].isListItem)
        XCTAssertEqual(lines[5].content, "일반 문단은 그대로 유지돼야 해")
    }

    func testAgentMarkdownTextInlineParsingRendersBoldAsAStrongRun() {
        let attributed = AgentMarkdownText.inlineAttributed("**제안 일정**: 오늘 일정을 제안해줄게.")
        // The bold marker characters themselves must not survive into the
        // rendered text -- exactly the symptom in the reported screenshot.
        XCTAssertFalse(String(attributed.characters).contains("**"))
        XCTAssertTrue(String(attributed.characters).contains("제안 일정"))

        let hasStrongRun = attributed.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        }
        XCTAssertTrue(hasStrongRun, "**제안 일정** must carry a bold run, not just plain text")
    }

    func testAgentMarkdownTextHandlesPlainTextWithNoMarkdown() {
        let lines = AgentMarkdownText.lines(for: "그냥 평범한 응답이에요.")
        XCTAssertEqual(lines.count, 1)
        XCTAssertFalse(lines[0].isListItem)
        XCTAssertEqual(lines[0].content, "그냥 평범한 응답이에요.")
    }

    func testAIConsentDefaultsToGrantedAndPersists() {
        let key = "memdo.v1.aiConsentGranted"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        // Opt-out, not opt-in -- the Agent feature was usable with no gate at
        // all before this flag existed, so a fresh install (no stored value)
        // must not suddenly go silent.
        XCTAssertTrue(AIConsent.granted)

        AIConsent.granted = false
        XCTAssertFalse(AIConsent.granted)
        AIConsent.granted = true
        XCTAssertTrue(AIConsent.granted)
    }

    @available(iOS 26, *)
    @MainActor
    func testUpdateScheduleToolResolvesTitleAndDetectsConflict() async throws {
        // buildScheduleContext() never puts real ids in the model's text
        // context, so UpdateScheduleTool has to resolve a bare title back to
        // a real item id itself (see its bestMatch(for:)) -- this exercises
        // that resolution plus its inline reschedule conflict check, both
        // private implementation details only reachable through call().
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: .now)
        let existing = [
            UpdateScheduleTool.ExistingItem(
                id: "id-1", title: "팀 회의",
                scheduledDate: today,
                startAt: cal.date(byAdding: .hour, value: 9, to: today),
                endAt: cal.date(byAdding: .hour, value: 10, to: today)
            ),
            UpdateScheduleTool.ExistingItem(
                id: "id-2", title: "점심 약속",
                scheduledDate: today,
                startAt: cal.date(byAdding: .hour, value: 12, to: today),
                endAt: cal.date(byAdding: .hour, value: 13, to: today)
            )
        ]

        let proposal = AgentScheduleUpdateProposal()
        let tool = UpdateScheduleTool(proposal: proposal, existing: existing)

        // Exact title match, no reschedule -> no conflict.
        _ = try await tool.call(arguments: .init(title: "팀 회의", action: "complete", date: "", startTime: "", endTime: ""))
        XCTAssertEqual(proposal.id, "id-1")
        XCTAssertEqual(proposal.action, "complete")
        XCTAssertNil(proposal.conflictTitle)
        proposal.clear()

        // Fuzzy (substring) title match still resolves to the right id.
        _ = try await tool.call(arguments: .init(title: "회의", action: "delete", date: "", startTime: "", endTime: ""))
        XCTAssertEqual(proposal.id, "id-1")
        proposal.clear()

        // Reschedule into an occupied slot surfaces the conflicting title.
        _ = try await tool.call(arguments: .init(title: "팀 회의", action: "reschedule", date: "today", startTime: "12:30", endTime: "13:00"))
        XCTAssertEqual(proposal.id, "id-1")
        XCTAssertEqual(proposal.conflictTitle, "점심 약속")
        proposal.clear()

        // No matching title -> nothing proposed.
        let result = try await tool.call(arguments: .init(title: "존재하지 않는 일정", action: "delete", date: "", startTime: "", endTime: ""))
        XCTAssertFalse(proposal.isPending)
        XCTAssertTrue(result.contains("찾지 못했어요"))
    }
}
