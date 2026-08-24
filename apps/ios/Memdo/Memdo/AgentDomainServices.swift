import Foundation

struct AgentTimeRange: Sendable, Equatable {
    let start: Date
    let end: Date
}

enum FreeSlotService {
    /// Same semantics, window-clipping, and service-level input contract as
    /// backend's freeSlotsInWindow -- see that doc comment (windowEnd<=windowStart,
    /// duration<=0, or maxResults<=0 all return []; busy ranges are clipped
    /// to [windowStart, windowEnd) before the gap walk, not just filtered).
    ///
    /// Returns at most one earliest duration-sized candidate per contiguous
    /// free gap between `busy` ranges inside [windowStart, windowEnd), capped
    /// at `maxResults`. Does NOT enumerate every possible slot within a gap
    /// -- a 3-hour gap with a 30-minute duration returns one 30-minute
    /// candidate at the gap's start, not six. Sorts `busy` and drops invalid
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

        let clipped = busy
            .map { AgentTimeRange(start: max($0.start, windowStart), end: min($0.end, windowEnd)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

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
}

func stageScheduleProposal(
    title: String,
    date: String,
    startTime: String,
    endTime: String,
    isTask: Bool,
    note: String,
    existing: [ConflictService.ExistingItem],
    conflictCheckFailed: Bool = false
) -> ScheduleProposalStagingResult {
    // Reject before staging anything -- an unparseable date must never
    // silently become "today" (Issue A-04).
    guard AgentDateExpression(token: date) != nil else { return .invalidDate }
    let draft = ProposedScheduleDraft(
        title: title,
        dateString: date,
        startTimeString: startTime.isEmpty ? nil : startTime,
        endTimeString: endTime.isEmpty ? nil : endTime,
        isTask: isTask,
        note: note.isEmpty ? nil : note
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
