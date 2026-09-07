import ActivityKit
import Foundation

/// Attributes for a user-initiated workout tracking Live Activity.
/// Shared between the Memdo app and MemdoWidget extension.
struct WorkoutTrackingAttributes: ActivityAttributes {
    typealias ContentState = TrackingState

    struct TrackingState: Codable, Hashable, Sendable {
        var isComplete: Bool
        var endedAt: Date?   // set only when isComplete == true
    }

    var workoutID: UUID
    var activityType: String   // WorkoutActivityType.rawValue
    var startedAt: Date
}
