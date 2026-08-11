import ActivityKit
import Foundation

/// Shared between the Memdo app and the MemdoWidget extension.
/// Must belong to BOTH targets.
struct MemdoScheduleAttributes: ActivityAttributes {
    typealias ContentState = ScheduleState

    struct ScheduleState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case upcoming, ongoing
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
