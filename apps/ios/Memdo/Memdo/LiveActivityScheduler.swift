import ActivityKit
import Foundation

enum LiveActivityScheduler {
    /// Start a Live Activity for an upcoming or ongoing schedule.
    /// Idempotent — ends any duplicate activity for the same scheduleID first.
    /// Noop when activities are disabled, schedule is done/ended, or starts more than 4 hours out.
    static func start(for schedule: ScheduleDetail) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let startAt = schedule.startAt, schedule.isActive, !schedule.isDone else { return }
        guard startAt < Date.now.addingTimeInterval(4 * 3600) else { return }
        if let endAt = schedule.endAt, endAt < .now { return }

        let id = schedule.id
        let title = schedule.title
        let colorName = schedule.color?.rawValue
        let kind: String = schedule.kind == .task ? "task" : "event"
        let endAt = schedule.endAt

        Task {
            for existing in Activity<MemdoScheduleAttributes>.activities
                where existing.attributes.scheduleID == id {
                await existing.end(nil, dismissalPolicy: .immediate)
            }

            let phase: MemdoScheduleAttributes.ScheduleState.Phase =
                startAt > .now ? .upcoming : .ongoing
            let state = MemdoScheduleAttributes.ScheduleState(
                title: title,
                colorName: colorName,
                kind: kind,
                startAt: startAt,
                endAt: endAt,
                phase: phase
            )
            let staleDate = (endAt ?? startAt.addingTimeInterval(3600)).addingTimeInterval(300)
            let content = ActivityContent(state: state, staleDate: staleDate)
            _ = try? Activity<MemdoScheduleAttributes>.request(
                attributes: MemdoScheduleAttributes(scheduleID: id),
                content: content,
                pushType: nil
            )
        }
    }

    /// Start Live Activities for all eligible upcoming schedules (app foreground hook).
    static func startUpcoming(from schedules: [ScheduleDetail]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        schedules.filter { !$0.isDone && $0.isActive }.forEach { start(for: $0) }
    }

    /// End a specific schedule's Live Activity (call on complete / cancel).
    static func end(for scheduleID: UUID) {
        Task {
            for activity in Activity<MemdoScheduleAttributes>.activities
                where activity.attributes.scheduleID == scheduleID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
