import ActivityKit
import Foundation

/// Shared between the Memdo app and the MemdoWidget extension.
/// Must belong to BOTH targets.
struct MemdoScheduleAttributes: ActivityAttributes {
    typealias ContentState = ScheduleState

    struct ScheduleState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case upcoming   // 시작 전 — 카운트다운
            case ongoing    // 진행 중 — 종료까지 카운트다운
            case done       // 완료 — 잠깐 표시 후 사라짐
        }

        var title: String
        var colorName: String?  // ScheduleColor.rawValue
        var kind: String        // "task" | "event"
        var startAt: Date
        var endAt: Date?
        var phase: Phase
    }

    var scheduleID: UUID
}
