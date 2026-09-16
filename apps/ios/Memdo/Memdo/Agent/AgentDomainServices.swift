import Foundation

struct AgentTimeRange: Sendable, Equatable {
    let start: Date
    let end: Date
}

enum FreeSlotService {
    private static func clippedSortedBusy(
        _ busy: [AgentTimeRange],
        windowStart: Date,
        windowEnd: Date
    ) -> [AgentTimeRange] {
        busy
            .map { AgentTimeRange(start: max($0.start, windowStart), end: min($0.end, windowEnd)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }

    /// Same semantics, window-clipping, and service-level input contract as
    /// backend's freeSlotsInWindow -- see that doc comment (windowEnd<=windowStart,
    /// duration<=0, or maxResults<=0 all return []; busy ranges are clipped
    /// to [windowStart, windowEnd) before the gap walk, not just filtered).
    ///
    /// This is the duration-constrained candidate-slot contract ("give me a
    /// slot to book something in") -- returns at most one earliest
    /// duration-sized candidate per contiguous free gap, capped at
    /// `maxResults`. Does NOT enumerate every possible slot within a gap --
    /// a 3-hour gap with a 30-minute duration returns one 30-minute
    /// candidate at the gap's start, not six. For "how free am I" (no
    /// duration constraint), use fullFreeExtents(_:) instead -- conflating
    /// the two here (e.g. via duration=0) was the actual bug behind an
    /// empty day answering "1 hour free" to a plain availability question
    /// (found during founder dogfooding). Sorts `busy` and drops invalid
    /// ranges (end <= start) internally; callers don't need to pre-sort or
    /// pre-filter.
    static func freeSlots(
        busy: [AgentTimeRange],
        windowStart: Date,
        windowEnd: Date,
        duration: TimeInterval,
        maxResults: Int = 3
    ) -> [AgentTimeRange] {
        guard windowEnd > windowStart, duration > 0, maxResults > 0 else { return [] }

        let clipped = clippedSortedBusy(busy, windowStart: windowStart, windowEnd: windowEnd)

        var slots: [AgentTimeRange] = []
        var cursor = windowStart
        for range in clipped {
            if range.start > cursor {
                if range.start.timeIntervalSince(cursor) >= duration {
                    slots.append(AgentTimeRange(start: cursor, end: cursor.addingTimeInterval(duration)))
                }
            }
            if range.end > cursor { cursor = range.end }
        }
        if windowEnd.timeIntervalSince(cursor) >= duration {
            slots.append(AgentTimeRange(start: cursor, end: cursor.addingTimeInterval(duration)))
        }

        return Array(slots.prefix(maxResults))
    }

    /// The availability-query contract ("how free am I") -- every contiguous
    /// free gap in [windowStart, windowEnd) reported in full, not sliced to
    /// any duration. An entirely empty window returns one extent spanning
    /// the whole window, not an arbitrary duration-sized piece of it. Same
    /// busy-clipping/sorting normalization as freeSlots (shared via
    /// clippedSortedBusy) so the two contracts never silently drift apart on
    /// what counts as "busy."
    static func fullFreeExtents(
        busy: [AgentTimeRange],
        windowStart: Date,
        windowEnd: Date
    ) -> [AgentTimeRange] {
        guard windowEnd > windowStart else { return [] }

        let clipped = clippedSortedBusy(busy, windowStart: windowStart, windowEnd: windowEnd)

        var extents: [AgentTimeRange] = []
        var cursor = windowStart
        for range in clipped {
            if range.start > cursor {
                extents.append(AgentTimeRange(start: cursor, end: range.start))
            }
            if range.end > cursor { cursor = range.end }
        }
        if windowEnd > cursor {
            extents.append(AgentTimeRange(start: cursor, end: windowEnd))
        }

        return extents
    }
}

enum ConflictService {
    /// ProposeScheduleTool.ExistingItem/UpdateScheduleTool.ExistingItem을 대체하는
    /// 단일 타입. `id`는 non-optional -- ExistingItem은 항상 scheduleStore.schedules의
    /// 실제 항목을 나타내고, 실제 항목은 항상 real id를 가진다. "제외할 대상 없음"은
    /// ExistingItem 개별 항목이 아니라 conflict(...)의 `excludingId: String?`가 nil인
    /// 것으로 표현한다(신규 생성=propose는 nil, 기존 항목 재조정=update는 자기 id).
    /// `scheduledDate`는 옮기지 않는다 -- 두 원본 타입 모두 이 필드를 실제로 읽는 곳이
    /// 없었다(grep으로 확인).
    struct ExistingItem: Sendable {
        let id: String
        let title: String
        let startAt: Date?
        let endAt: Date?
    }

    /// Pure interval-overlap detection -- the first existing item (in
    /// `existing`'s input order, NOT sorted by time) whose interval overlaps
    /// `interval`, or nil. `excludingId` skips one item (the item being
    /// rescheduled must not conflict with itself). Items with no
    /// startAt/endAt (tasks, all-day) are skipped -- nothing to overlap.
    static func conflict(
        for interval: AgentTimeRange,
        excludingId: String? = nil,
        in existing: [ExistingItem]
    ) -> ExistingItem? {
        existing.first { item in
            if let excludingId, item.id == excludingId { return false }
            guard let itemStart = item.startAt, let itemEnd = item.endAt else { return false }
            return interval.start < itemEnd && interval.end > itemStart
        }
    }
}

/// id+title bundled into one optional value instead of two independent
/// optionals (`conflictId`/`conflictTitle`) -- "id is set but title isn't"
/// is not a state either AgentScheduleProposal/AgentScheduleUpdateProposal
/// can be in.
struct AgentConflictSnapshot: Sendable, Equatable {
    let id: String
    let title: String
}

enum ConflictRevalidationDecision: Equatable {
    case proceed
    case refresh(AgentConflictSnapshot)
}

/// Shared by confirmProposal(_:)/confirmScheduleUpdateProposal() (Issue
/// C-04) -- compares the conflict snapshot captured at staging time (which
/// may itself already be stale: on-device Tools hold whatever snapshot
/// existed when the LanguageModelSession's tools were constructed, not
/// necessarily "now") against one freshly recomputed at confirm time
/// against scheduleStore.schedules. The guarantee C-04 provides is this
/// confirm-time recomputation, not that staging was fresh.
///
/// Comparison is by `id` (stable identity), not `title` -- a same-titled
/// but different schedule replacing the staged conflict must not be
/// mistaken for "unchanged". A conflict disappearing between staging and
/// confirm is treated as benign (risk went down, not up) and proceeds
/// without requiring re-approval; only a new or different conflict blocks
/// this tap and asks the user to approve again having seen it.
///
/// Known limitation: ConflictService.conflict(...) returns the first match
/// in `existing`'s input order, not sorted by time (see ConflictService's
/// doc comment). If the set of actual conflicts is unchanged but
/// scheduleStore.schedules' order shifts between staging and confirm, the
/// "first match" id can change even though nothing riskier happened --
/// this reads as `.refresh` (a conservative extra tap) rather than
/// `.proceed`. This is a consequence of the "first match" contract, not a
/// bug, and isn't worth a different conflict-selection policy just to
/// avoid it.
func conflictRevalidationDecision(
    staged: AgentConflictSnapshot?,
    fresh: AgentConflictSnapshot?
) -> ConflictRevalidationDecision {
    switch (staged, fresh) {
    case (_, nil): return .proceed
    case (nil, let fresh?): return .refresh(fresh)
    case (let staged?, let fresh?) where staged.id == fresh.id: return .proceed
    case (_, let fresh?): return .refresh(fresh)
    }
}

// MARK: - Provider-neutral proposal staging (Epic D-2)
//
// ProposeScheduleTool.call(arguments:) (on-device) and
// AssistantView.ingestCloudResult (cloud) used to each run their own copy of
// "validate -> build draft -> compute conflict -> stage" -- nearly identical
// code, duplicated because each provider produces its raw input differently
// (FoundationModels @Generable Arguments vs a decoded cloud DTO) even though
// what happens to that input once it's provider-neutral strings/values is
// the same. The functions below are that shared middle step. They are pure
// -- they never touch AgentScheduleProposal/AgentScheduleUpdateProposal
// themselves; callers take the result and call propose(...) on their own
// proposal reference, the same way ConflictService/FreeSlotService above
// stay pure and let their callers own all state.

enum ScheduleProposalStagingResult: Equatable {
    case staged(ProposedScheduleDraft, conflict: AgentConflictSnapshot?, conflictCheckFailed: Bool)
    case invalidDate
    /// bd4: an event (isTask: false) has a start time but the model left
    /// endTime empty, AND the default-duration logic below can't produce a
    /// valid same-day end for this specific start (only possible when
    /// startTime is exactly "23:59" -- one-minute granularity leaves zero
    /// representable minutes after it on the same day). Staging anyway with
    /// endTimeString nil would recreate the exact "approved but can't be
    /// saved" bug this fix exists to eliminate, so nothing is staged at all
    /// -- the caller shows a targeted clarifying question instead.
    case needsEndTime
}

func stageScheduleProposal(
    title: String,
    date: String,
    startTime: String,
    endTime: String,
    isTask: Bool,
    note: String,
    existing: [ConflictService.ExistingItem],
    conflictCheckFailed: Bool = false,
    // A1-2: cloud-only fields, defaulted so the on-device call site
    // (ProposeScheduleTool.call(arguments:), which doesn't produce any of
    // these) needs no change. Same trust-boundary re-validation stance as
    // `date` above -- agent-tool-contract.ts's proposeScheduleArgsSchema
    // already rejects an invalid shape server-side, this defends against
    // client/backend version skew, not a distrusted healthy backend.
    dueDate: String? = nil,
    dueTime: String? = nil,
    estimatedMinutes: Int? = nil,
    reminderOffsetsMinutes: [Int] = [],
    locationQuery: String? = nil,
    categoryHint: String? = nil
) -> ScheduleProposalStagingResult {
    // Reject before staging anything -- an unparseable date must never
    // silently become "today" (Issue A-04).
    guard AgentDateExpression(token: date) != nil else { return .invalidDate }
    // Mirrors proposeScheduleArgsSchema's task-only-due-date and
    // dueTime-requires-dueDate rules -- never silently drop an
    // inconsistent due proposal by treating it as "no due date."
    if let dueDate {
        guard isTask, AgentDateExpression(token: dueDate) != nil else { return .invalidDate }
    } else if dueTime != nil {
        return .invalidDate
    }

    // bd4: an event proposal with a start time but no end time used to
    // stage with endTimeString nil -- ProposedScheduleCard's displayTime
    // then showed just the bare start time with no end at all, the user
    // approved exactly that, and toScheduleDetail() silently defaulted
    // endAt to start+1h only at *save* time (a value the user never saw or
    // approved). Defaulting here instead, before ProposedScheduleDraft is
    // ever constructed, means the draft/card/save all read the same
    // resolved value -- informed consent, not a same-time coincidence.
    var resolvedEndTime = endTime
    if !isTask, !startTime.isEmpty, endTime.isEmpty {
        guard let proposalDate = AgentDateExpression(token: date)?.resolvedDate(),
              let start = parseAgentTime(startTime, on: proposalDate)
        else { return .invalidDate }
        let endOfDay = Calendar.current.date(
            bySettingHour: 23, minute: 59, second: 0, of: proposalDate
        ) ?? proposalDate
        let candidateEnd = min(start.addingTimeInterval(3_600), endOfDay)
        // Only possible when start == 23:59 -- see .needsEndTime's doc
        // comment. Every start before 23:59 (including 23:58) clamps to a
        // valid, non-zero duration.
        guard candidateEnd > start else { return .needsEndTime }
        resolvedEndTime = formatAgentTime(candidateEnd)
    }

    let draft = ProposedScheduleDraft(
        title: title,
        dateString: date,
        startTimeString: startTime.isEmpty ? nil : startTime,
        endTimeString: resolvedEndTime.isEmpty ? nil : resolvedEndTime,
        isTask: isTask,
        note: note.isEmpty ? nil : note,
        dueDateString: dueDate,
        dueTimeString: dueTime,
        estimatedMinutes: estimatedMinutes,
        reminderOffsetsMinutes: reminderOffsetsMinutes,
        locationQuery: locationQuery,
        categoryHint: categoryHint
    )
    // Reflection step: check the proposal against the real schedule before
    // handing it back, instead of presenting it uncritically.
    let conflict = draft.resolvedInterval().flatMap { interval in
        ConflictService.conflict(for: AgentTimeRange(start: interval.start, end: interval.end), in: existing)
    }
    return .staged(
        draft,
        conflict: conflict.map { AgentConflictSnapshot(id: $0.id, title: $0.title) },
        conflictCheckFailed: conflictCheckFailed
    )
}

/// A3-1/A3-2/A3-3: stages every item in a propose_schedule_batch response
/// independently, reusing stageScheduleProposal per item completely
/// unchanged -- each item gets the exact same date/dueDate/endTime
/// validation and conflict-check Reflection a lone propose_schedule call
/// already gets, computed fresh against the current local schedule (never
/// trusting the server's own staging-time conflictTitle, same C-04 stance
/// as every other proposal kind). An item that fails validation
/// (invalidDate/needsEndTime) is dropped from the returned array instead of
/// failing the whole batch -- the client-side mirror of A3-2's "one bad
/// item never blocks the others" contract, since staging here happens
/// against fresh local state the server never saw.
func stageScheduleBatchProposal(
    items: [CloudProposedScheduleBatchItemDTO],
    existing: [ConflictService.ExistingItem]
) -> [AgentScheduleBatchItem] {
    items.compactMap { item in
        let result = stageScheduleProposal(
            title: item.title,
            date: item.scheduledDate,
            startTime: item.startTime ?? "",
            endTime: item.endTime ?? "",
            isTask: item.entryKind == "task",
            note: item.note ?? "",
            existing: existing,
            conflictCheckFailed: item.conflictCheckFailed ?? false,
            dueDate: item.dueDate,
            dueTime: item.dueTime,
            estimatedMinutes: item.estimatedMinutes,
            reminderOffsetsMinutes: item.reminderOffsetsMinutes ?? [],
            locationQuery: item.locationQuery,
            categoryHint: item.categoryHint
        )
        switch result {
        case .staged(let draft, let conflict, let conflictCheckFailed):
            return AgentScheduleBatchItem(draft: draft, conflict: conflict, conflictCheckFailed: conflictCheckFailed)
        case .invalidDate, .needsEndTime:
            return nil
        }
    }
}

enum ScheduleUpdateStagingResult: Equatable {
    case staged(
        id: String, action: AgentUpdateAction, title: String,
        dateString: String?, startTimeString: String?, endTimeString: String?,
        conflict: AgentConflictSnapshot?, conflictCheckFailed: Bool
    )
    case invalidDate
}

/// `id`/`title` are already resolved by the caller (on-device:
/// UpdateScheduleTool.bestMatch(for:); cloud: echoed back from
/// search_schedules) -- that resolution step is provider-specific and stays
/// out of this shared boundary. `action` is the already-validated
/// AgentUpdateAction, not a raw model/DTO string -- see rescheduleConflict's
/// doc comment for why a String here would be a step backwards.
func stageScheduleUpdate(
    id: String,
    title: String,
    action: AgentUpdateAction,
    dateString: String?,
    startTimeString: String?,
    endTimeString: String?,
    existing: [ConflictService.ExistingItem],
    conflictCheckFailed: Bool = false
) -> ScheduleUpdateStagingResult {
    // Reschedule requires a real target date -- a missing or unparseable one
    // must be rejected outright, not silently treated as today (Issue
    // A-04). complete/delete never carry a date. Unlike the pre-D-2 cloud
    // ingestion code (which only checked "if a date is present, is it
    // valid" and relied entirely on the backend's Zod schema to guarantee
    // reschedule always sends one), this also enforces the "reschedule
    // requires a date" half explicitly -- matching what the on-device path
    // already enforced on its own. A client/backend version skew could
    // otherwise let a dateless reschedule through on the cloud path; this
    // closes that gap for both providers, not just preserves on-device's.
    let dateIsValid: Bool
    if let dateString {
        dateIsValid = AgentDateExpression(token: dateString) != nil
    } else {
        dateIsValid = action != .reschedule
    }
    guard dateIsValid else { return .invalidDate }

    let conflict = rescheduleConflict(
        action: action,
        excludingId: id,
        dateString: dateString,
        startTimeString: startTimeString,
        endTimeString: endTimeString,
        existing: existing
    )
    return .staged(
        id: id, action: action, title: title,
        dateString: dateString, startTimeString: startTimeString, endTimeString: endTimeString,
        conflict: conflict.map { AgentConflictSnapshot(id: $0.id, title: $0.title) },
        conflictCheckFailed: conflictCheckFailed
    )
}

/// A2-2/A2-3: applies an approved propose_schedule_edit's changes onto the
/// CURRENT live copy of the item (`schedule` must be read from
/// scheduleStore.schedules at confirm time, never the staging-time
/// snapshot the server echoed back in `current`) -- only fields actually
/// proposed are touched, everything else on `schedule` passes through
/// unchanged, including its `version`. Reading the live copy is what gives
/// A2-2's version-safety property for free: `schedule.version` is
/// whatever the local store currently holds, so the eventual
/// ScheduleStore.save() call naturally revalidates against the item's
/// CURRENT state (via the same optimistic-lock VERSION_CONFLICT path
/// every other write already goes through), not the state that existed
/// when the proposal was first staged.
///
/// `resolvedLocation` is separate from `edit.locationQuery` on purpose --
/// A1-3's on-device MapKit resolution (AssistantView.resolveMapLocation)
/// is async and this function stays pure/synchronous; nil falls back to a
/// manual-provider ScheduleLocation (a name only), the same default
/// ProposedScheduleDraft.toScheduleDetail() already uses for create
/// proposals when MapKit resolves nothing.
func applyScheduleEdit(
    _ edit: CloudProposedScheduleEditDTO,
    to schedule: ScheduleDetail,
    resolvedLocation: ScheduleLocation? = nil
) -> ScheduleDetail {
    var updated = schedule
    if let reminderOffsetsMinutes = edit.reminderOffsetsMinutes {
        updated.reminderOffsetsMinutes = reminderOffsetsMinutes
    }
    if let dueDateToken = edit.dueDate, let expr = AgentDateExpression(token: dueDateToken) {
        let day = expr.resolvedDate()
        if let dueTimeString = edit.dueTime, let time = parseAgentTime(dueTimeString, on: day) {
            updated.dueAt = time
        } else {
            // No specific time stated -- end-of-day, same fallback R1-5's
            // due-anchor reminder default and ProposedScheduleDraft.dueAt()
            // already use.
            updated.dueAt = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
        }
    }
    if let estimatedMinutes = edit.estimatedMinutes {
        updated.estimatedMinutes = estimatedMinutes
    }
    if let locationQuery = edit.locationQuery, !locationQuery.isEmpty {
        updated.locationValue = resolvedLocation ?? ScheduleLocation(name: locationQuery, provider: .manual)
    }
    if let note = edit.note {
        updated.memo = note
    }
    // categoryId intentionally never applied here, even though A1-3
    // resolves one server-side -- same "display-only, never auto-applied"
    // stance as propose_schedule's own categoryHint (see
    // CloudProposedScheduleEditDTO's doc comment).
    return updated
}

/// Shared by staging (stageScheduleUpdate, called from both the on-device
/// Tool and cloud ingestion) and confirm-time revalidation (Issue C-04) so a
/// reschedule's conflict is computed identically everywhere -- previously
/// UpdateScheduleTool.call(arguments:) had its own separate inline copy of
/// this while cloud ingestion and confirm-time already shared one (as an
/// AssistantView-private method); this is that method, moved here so
/// on-device can use it too.
func rescheduleConflict(
    action: AgentUpdateAction,
    excludingId: String,
    dateString: String?,
    startTimeString: String?,
    endTimeString: String?,
    existing: [ConflictService.ExistingItem]
) -> ConflictService.ExistingItem? {
    guard action == .reschedule,
          let dateString, let expr = AgentDateExpression(token: dateString),
          let startTimeString, !startTimeString.isEmpty,
          let start = parseAgentTime(startTimeString, on: expr.resolvedDate())
    else { return nil }
    let end = endTimeString.flatMap { parseAgentTime($0, on: expr.resolvedDate()) } ?? start.addingTimeInterval(3_600)
    return ConflictService.conflict(
        for: AgentTimeRange(start: start, end: end),
        excludingId: excludingId,
        in: existing
    )
}

// MARK: - Routine-update proposal staging (Epic I)

/// Applies a propose_routine_update proposal as a PARTIAL merge -- only the
/// fields present in `proposal` are changed; every other field on
/// `preferences` (including ones this tool can never propose, like
/// dailyReviewDays/dailyReviewIncludeReflection) passes through untouched.
/// Pure so the merge logic is verifiable without a real PreferencesStore.
func applyRoutineUpdate(_ proposal: CloudProposedRoutineUpdateDTO, to preferences: UserPreferences) -> UserPreferences {
    var updated = preferences
    if let dailyReviewEnabled = proposal.dailyReviewEnabled { updated.dailyReviewEnabled = dailyReviewEnabled }
    if let dailyReviewTime = proposal.dailyReviewTime { updated.dailyReviewTime = dailyReviewTime }
    if let newsBriefingEnabled = proposal.newsBriefingEnabled { updated.newsBriefingEnabled = newsBriefingEnabled }
    if let newsBriefingTime = proposal.newsBriefingTime { updated.newsBriefingTime = newsBriefingTime }
    if let planningPromptTime = proposal.planningPromptTime { updated.planningPromptTime = planningPromptTime }
    if let notificationsEnabled = proposal.notificationsEnabled { updated.notificationsEnabled = notificationsEnabled }
    return updated
}
