import ActivityKit
import Foundation

/// Manages the user-initiated workout tracking Live Activity.
/// Only workouts the user explicitly chooses to track get a Live Activity.
enum WorkoutActivityTracker {

    /// Start a Live Activity for a workout the user is about to begin.
    static func start(workoutID: UUID, activityType: String, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            // End any stale activity for this workout before starting a new one
            for activity in Activity<WorkoutTrackingAttributes>.activities
                where activity.attributes.workoutID == workoutID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            let attrs = WorkoutTrackingAttributes(
                workoutID: workoutID,
                activityType: activityType,
                startedAt: startedAt
            )
            let state = WorkoutTrackingAttributes.TrackingState(isComplete: false, endedAt: nil)
            _ = try? Activity<WorkoutTrackingAttributes>.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        }
    }

    /// Mark the workout as complete. The Live Activity shows a done state for 5 min then dismisses.
    static func complete(workoutID: UUID, endedAt: Date = .now) {
        Task {
            for activity in Activity<WorkoutTrackingAttributes>.activities
                where activity.attributes.workoutID == workoutID {
                let doneState = WorkoutTrackingAttributes.TrackingState(
                    isComplete: true,
                    endedAt: endedAt
                )
                let dismissAt = endedAt.addingTimeInterval(300)
                await activity.end(
                    ActivityContent(state: doneState, staleDate: dismissAt),
                    dismissalPolicy: .after(dismissAt)
                )
            }
        }
    }

    /// Immediately end a workout's Live Activity (e.g. user cancelled).
    static func cancel(workoutID: UUID) {
        Task {
            for activity in Activity<WorkoutTrackingAttributes>.activities
                where activity.attributes.workoutID == workoutID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Whether a Live Activity is currently running for the given workout.
    static func isTracking(workoutID: UUID) -> Bool {
        Activity<WorkoutTrackingAttributes>.activities
            .contains { $0.attributes.workoutID == workoutID && !$0.content.state.isComplete }
    }
}
