import XCTest
import UIKit
import os
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

    @MainActor
    func testGroupedByOccurrenceDayCountsAMultiDayEventOnEveryDayItSpans() throws {
        // CalendarView.scheduleCounts and ScheduleModel.updateWidgetSnapshot
        // both independently pre-filtered then ran this exact day-by-day
        // scan -- this pins the shared version's core reason for existing: a
        // flat range filter on scheduledDate would only find this event on
        // its start day, undercounting every day it actually spans.
        let systemCalendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 23)))
        let end = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 1)))
        let trip = ScheduleDetail(scheduledDate: start, startAt: start, endAt: end, title: "출장", calendar: calendar)

        let monthStart = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let monthEnd = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let byDay = ScheduleStore.groupedByOccurrenceDay(
            [trip],
            in: DateInterval(start: monthStart, end: monthEnd),
            calendar: systemCalendar
        )

        let day9 = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 9)))
        let day10 = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let day11 = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))
        let day12 = try XCTUnwrap(systemCalendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))

        XCTAssertEqual(byDay[day9]?.count, 1)
        XCTAssertEqual(byDay[day10]?.count, 1)
        XCTAssertEqual(byDay[day11]?.count, 1)
        XCTAssertNil(byDay[day12])
    }

    func testDateFormattingKoreanUsesKoreanLocale() {
        // AssistantView/SlackNotifier/NotificationScheduler/BriefingFeed each
        // used to build their own DateFormatter and set this locale by hand.
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        XCTAssertEqual(DateFormatting.korean("M월 d일").string(from: date), "8월 20일")
    }

    func testDateFormattingPosixParsesRegardlessOfDeviceLocale() {
        // AssistantView's two "yyyy-MM-dd" parse sites (AgentDateExpression.init?,
        // FindFreeSlotTool.validScopeDates) and BriefingFeed's currentDateString()
        // built a bare DateFormatter() with no locale at all -- Apple's
        // documented fix for "fixed-format" parsing being silently affected
        // by the device's actual locale/calendar is `en_US_POSIX`, which
        // DateFormatting.posix now applies for all of them.
        let formatter = DateFormatting.posix("yyyy-MM-dd")
        let parsed = formatter.date(from: "2026-08-20")
        XCTAssertNotNil(parsed)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: parsed!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 20)
    }

    func testHasValidTitleRejectsWhitespaceOnly() {
        // Two save-gate call sites (ScheduleSheets.swift) used to each
        // re-derive `!title.trimmingCharacters(...).isEmpty` inline -- this
        // pins the shared property's whitespace handling now that both
        // route through it instead.
        let day = Date()
        let blank = ScheduleDetail(scheduledDate: day, title: "   ", kind: .task, calendar: calendar)
        let real = ScheduleDetail(scheduledDate: day, title: "  진짜 제목  ", kind: .task, calendar: calendar)
        let empty = ScheduleDetail(scheduledDate: day, title: "", kind: .task, calendar: calendar)

        XCTAssertFalse(blank.hasValidTitle)
        XCTAssertFalse(empty.hasValidTitle)
        XCTAssertTrue(real.hasValidTitle)
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

    func testAgentCloudHistoryExcludesCurrentTurnAndUnsettledMessages() {
        // send()/retry() both append (or leave) the current user turn as
        // messages.last before calling this -- it must drop that trailing
        // turn or the same turn gets sent twice (once as the last history
        // entry, once again as the request's separate `message` field).
        let previousUser = AgentMessage(role: .user, text: "이전 질문")
        let previousAssistant = AgentMessage(role: .assistant, text: "이전 답변")
        let currentUser = AgentMessage(role: .user, text: "현재 질문")

        XCTAssertEqual(
            agentCloudHistory(from: [previousUser, previousAssistant, currentUser]).map(\.content),
            ["이전 질문", "이전 답변"]
        )

        let errorAssistant = AgentMessage(role: .assistant, text: "오류", isError: true)
        XCTAssertEqual(
            agentCloudHistory(from: [previousUser, errorAssistant, currentUser]).map(\.content),
            ["이전 질문"]
        )

        let streamingAssistant = AgentMessage(role: .assistant, text: "...", isStreaming: true)
        XCTAssertEqual(
            agentCloudHistory(from: [previousUser, streamingAssistant, currentUser]).map(\.content),
            ["이전 질문"]
        )
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
            conflict: AgentConflictSnapshot(id: "conflict-1", title: "다른 일정"),
            conflictCheckFailed: false
        )

        XCTAssertTrue(proposal.isPending)
        XCTAssertEqual(proposal.displayActionLabel, "일정 변경")
        XCTAssertEqual(proposal.displayDate, "내일")
        XCTAssertEqual(proposal.conflict?.title, "다른 일정")

        proposal.clear()
        XCTAssertFalse(proposal.isPending)
        XCTAssertNil(proposal.action)
        XCTAssertNil(proposal.conflict)
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
                conflict: nil, conflictCheckFailed: false
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
            ConflictService.ExistingItem(
                id: "id-1", title: "팀 회의",
                startAt: cal.date(byAdding: .hour, value: 9, to: today),
                endAt: cal.date(byAdding: .hour, value: 10, to: today)
            ),
            ConflictService.ExistingItem(
                id: "id-2", title: "점심 약속",
                startAt: cal.date(byAdding: .hour, value: 12, to: today),
                endAt: cal.date(byAdding: .hour, value: 13, to: today)
            )
        ]

        let proposal = AgentScheduleUpdateProposal()
        let tool = UpdateScheduleTool(proposal: proposal, existingProvider: { existing })

        // Exact title match, no reschedule -> no conflict.
        _ = try await tool.call(arguments: .init(title: "팀 회의", action: "complete", date: "", startTime: "", endTime: ""))
        XCTAssertEqual(proposal.id, "id-1")
        XCTAssertEqual(proposal.action, "complete")
        XCTAssertNil(proposal.conflict)
        proposal.clear()

        // Fuzzy (substring) title match still resolves to the right id.
        _ = try await tool.call(arguments: .init(title: "회의", action: "delete", date: "", startTime: "", endTime: ""))
        XCTAssertEqual(proposal.id, "id-1")
        proposal.clear()

        // Reschedule into an occupied slot surfaces the conflicting title.
        _ = try await tool.call(arguments: .init(title: "팀 회의", action: "reschedule", date: "today", startTime: "12:30", endTime: "13:00"))
        XCTAssertEqual(proposal.id, "id-1")
        XCTAssertEqual(proposal.conflict?.title, "점심 약속")
        proposal.clear()

        // No matching title -> nothing proposed.
        let result = try await tool.call(arguments: .init(title: "존재하지 않는 일정", action: "delete", date: "", startTime: "", endTime: ""))
        XCTAssertFalse(proposal.isPending)
        XCTAssertTrue(result.contains("찾지 못했어요"))
    }

    @available(iOS 26, *)
    @MainActor
    func test_reschedule_selfOnlyConflict() async throws {
        // Issue C-04 Acceptance Criteria #8: reschedule must exclude the
        // target's own (pre-move) row -- with only itself in `existing`,
        // moving it to overlap its own current time must never read as a
        // self-conflict.
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: .now)
        let existing = [
            ConflictService.ExistingItem(
                id: "id-1", title: "팀 회의",
                startAt: cal.date(byAdding: .hour, value: 9, to: today),
                endAt: cal.date(byAdding: .hour, value: 10, to: today)
            ),
        ]
        let proposal = AgentScheduleUpdateProposal()
        let tool = UpdateScheduleTool(proposal: proposal, existingProvider: { existing })

        _ = try await tool.call(arguments: .init(title: "팀 회의", action: "reschedule", date: "today", startTime: "09:00", endTime: "10:00"))
        XCTAssertEqual(proposal.id, "id-1")
        XCTAssertNil(proposal.conflict)
    }

    func testAgentDateExpressionRejectsInvalidTokens() {
        XCTAssertNil(AgentDateExpression(token: "2026-99-40"))
        XCTAssertNil(AgentDateExpression(token: "banana"))
        XCTAssertNil(AgentDateExpression(token: "someday"))
        XCTAssertEqual(AgentDateExpression(token: "today"), .today)
        XCTAssertEqual(AgentDateExpression(token: "tomorrow"), .tomorrow)
        XCTAssertNotNil(AgentDateExpression(token: "2026-09-01"))
    }

    func testAgentUpdateActionRejectsUnknownValues() {
        XCTAssertNil(AgentUpdateAction(rawValue: "cancel"))
        XCTAssertNil(AgentUpdateAction(rawValue: ""))
        XCTAssertEqual(AgentUpdateAction(rawValue: "complete"), .complete)
        XCTAssertEqual(AgentUpdateAction(rawValue: "reschedule"), .reschedule)
        XCTAssertEqual(AgentUpdateAction(rawValue: "delete"), .delete)
    }

    @available(iOS 26, *)
    @MainActor
    func testUpdateScheduleToolRejectsInvalidActionOrRescheduleDate() async throws {
        // Issue A-04: an invalid action or an unparseable/missing reschedule
        // date must never reach updateProposal -- checking the returned
        // string alone isn't enough, since a bug could return an error
        // while still having mutated state first (mutation-absence).
        let existing = [
            ConflictService.ExistingItem(id: "id-1", title: "팀 회의", startAt: nil, endAt: nil),
        ]
        let proposal = AgentScheduleUpdateProposal()
        let tool = UpdateScheduleTool(proposal: proposal, existingProvider: { existing })

        _ = try await tool.call(arguments: .init(title: "팀 회의", action: "cancel", date: "", startTime: "", endTime: ""))
        XCTAssertFalse(proposal.isPending)

        _ = try await tool.call(arguments: .init(title: "팀 회의", action: "reschedule", date: "", startTime: "", endTime: ""))
        XCTAssertFalse(proposal.isPending)

        _ = try await tool.call(arguments: .init(title: "팀 회의", action: "reschedule", date: "banana", startTime: "", endTime: ""))
        XCTAssertFalse(proposal.isPending)
    }

    @available(iOS 26, *)
    @MainActor
    func testProposeScheduleToolRejectsInvalidDate() async throws {
        let proposal = AgentScheduleProposal()
        let tool = ProposeScheduleTool(proposal: proposal, existingProvider: { [] })

        let result = try await tool.call(arguments: .init(
            title: "치과", date: "banana", startTime: "15:00", endTime: "", isTask: false, note: ""
        ))
        XCTAssertNil(proposal.draft)
        XCTAssertTrue(result.contains("이해하지 못했어요"))
    }

    @available(iOS 26, *)
    func testFindFreeSlotToolRejectsScopeAndDurationOutsideContract() async throws {
        // Same 15...480 minute bound the backend's findFreeSlotsArgsSchema
        // enforces (Issue A-04/B-04) -- neither end should be silently
        // clamped into range, both must be rejected outright.
        let tool = FindFreeSlotTool(snapshotProvider: { [] })

        let badScope = try await tool.call(arguments: .init(scope: "someday", durationMinutes: 30, windowStart: "", windowEnd: ""))
        XCTAssertTrue(badScope.contains("이해하지 못했어요"))

        let tooShort = try await tool.call(arguments: .init(scope: "today", durationMinutes: 5, windowStart: "", windowEnd: ""))
        XCTAssertTrue(tooShort.contains("짧거나 길어요"))

        let tooLong = try await tool.call(arguments: .init(scope: "today", durationMinutes: 999, windowStart: "", windowEnd: ""))
        XCTAssertTrue(tooLong.contains("짧거나 길어요"))
    }

    // Absence of durationMinutes means "how free am I" (availability query),
    // not "duration unspecified, guess one" -- never silently defaulted.
    // Found during founder dogfooding: an empty day used to answer "언제
    // 비어 있어?" with a single arbitrary duration-sized slot instead of the
    // whole open window.
    @available(iOS 26, *)
    func testFindFreeSlotToolWithNoDurationOnEmptyDayAnswersAvailabilityNotADurationSlice() async throws {
        let tool = FindFreeSlotTool(snapshotProvider: { [] })
        let result = try await tool.call(arguments: .init(scope: "today", durationMinutes: nil, windowStart: "", windowEnd: ""))
        // No "등록된 일정이 없어서" causal claim -- busyRanges(_:) only looks
        // at timed items, so this wording must stay true even when an
        // untimed task exists (see the dedicated test below).
        XCTAssertFalse(result.contains("등록된 일정이 없어서"))
        XCTAssertTrue(result.contains("전체가 비어 있어요"))
    }

    // D1-2: an untimed task is invisible to busyRanges(_:) (only startAt/
    // endAt-having items count as busy), so the wording must not claim "no
    // schedules registered" just because the timed calendar is empty --
    // this task genuinely IS a registered schedule.
    @available(iOS 26, *)
    func testFindFreeSlotToolAvailabilityWordingStaysTruthfulWithAnUntimedTask() async throws {
        let day = Calendar.current.startOfDay(for: .now)
        let tool = FindFreeSlotTool(snapshotProvider: {
            [.init(scheduledDate: day, startAt: nil, endAt: nil)]
        })
        let result = try await tool.call(arguments: .init(scope: "today", durationMinutes: nil, windowStart: "", windowEnd: ""))
        XCTAssertFalse(result.contains("등록된 일정이 없어서"))
        XCTAssertTrue(result.contains("전체가 비어 있어요"))
    }

    @available(iOS 26, *)
    func testFindFreeSlotToolWithNoDurationAndOneEventListsBothFreeExtents() async throws {
        let day = Calendar.current.startOfDay(for: .now)
        let busyStart = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let busyEnd = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: day)!
        let tool = FindFreeSlotTool(snapshotProvider: {
            [.init(scheduledDate: day, startAt: busyStart, endAt: busyEnd)]
        })
        let result = try await tool.call(arguments: .init(scope: "today", durationMinutes: nil, windowStart: "", windowEnd: ""))
        XCTAssertFalse(result.contains("등록된 일정이 없어서"))
        XCTAssertEqual(result.components(separatedBy: ",").count, 2)
    }

    @available(iOS 26, *)
    func testFindFreeSlotToolWithExplicitDurationStillReturnsOneCandidateSlot() async throws {
        let tool = FindFreeSlotTool(snapshotProvider: { [] })
        let result = try await tool.call(arguments: .init(scope: "today", durationMinutes: 60, windowStart: "", windowEnd: ""))
        XCTAssertFalse(result.contains("등록된 일정이 없어서"))
        XCTAssertEqual(result.components(separatedBy: ",").count, 1)
    }

    // D4 second-pass review: onFinish is reported via `defer`, specifically
    // so it fires on every exit path of call(arguments:) -- including an
    // early `return` from a validation failure -- not just the "happy
    // path" success return. This pins that guarantee for the bad-scope
    // early-return branch (the same one exercised above), where a naive
    // "call onFinish right before each return statement" implementation
    // would be easy to accidentally miss on one branch.
    @available(iOS 26, *)
    func testFindFreeSlotToolReportsFinishEvenOnAnEarlyValidationReturn() async throws {
        let started = OSAllocatedUnfairLock(initialState: [AgentCapability]())
        let finished = OSAllocatedUnfairLock(initialState: [AgentCapability]())
        let tool = FindFreeSlotTool(
            snapshotProvider: { [] },
            onStart: { capability in started.withLock { $0.append(capability) } },
            onFinish: { capability in finished.withLock { $0.append(capability) } }
        )
        _ = try await tool.call(arguments: .init(scope: "not-a-real-scope", durationMinutes: 30, windowStart: "", windowEnd: ""))
        XCTAssertEqual(started.withLock { $0 }.count, 1)
        XCTAssertEqual(finished.withLock { $0 }.count, 1)
    }

    // MARK: - Live schedule-state providers (Epic D-2)

    @available(iOS 26, *)
    @MainActor
    func testUpdateScheduleToolReadsLiveExistingItemsNotAConstructionTimeSnapshot() async throws {
        // Regression coverage for the staleness this Tool used to have: the
        // old `existing: [ConflictService.ExistingItem]` was captured once
        // when the Tool (and its LanguageModelSession) was constructed, and
        // never changed for the rest of that session. existingProvider is a
        // closure the Tool calls fresh on every call(arguments:) -- this
        // mutates what it returns between two calls on the *same* Tool
        // instance and checks the second call actually sees the change.
        var currentExisting: [ConflictService.ExistingItem] = [
            ConflictService.ExistingItem(id: "id-1", title: "팀 회의", startAt: nil, endAt: nil),
        ]
        let proposal = AgentScheduleUpdateProposal()
        let tool = UpdateScheduleTool(proposal: proposal, existingProvider: { currentExisting })

        _ = try await tool.call(arguments: .init(title: "새 일정", action: "complete", date: "", startTime: "", endTime: ""))
        XCTAssertFalse(proposal.isPending, "'새 일정' shouldn't match anything in the original snapshot")

        // A schedule named "새 일정" gets added after the Tool/session already
        // exists -- exactly what happens when the user creates something
        // mid-conversation on-device.
        currentExisting.append(.init(id: "id-2", title: "새 일정", startAt: nil, endAt: nil))

        _ = try await tool.call(arguments: .init(title: "새 일정", action: "complete", date: "", startTime: "", endTime: ""))
        XCTAssertEqual(proposal.id, "id-2", "the same Tool instance's second call should see the newly-added item")
    }
}
