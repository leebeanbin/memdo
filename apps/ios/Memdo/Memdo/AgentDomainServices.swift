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
