import ActivityKit
import Foundation

enum LiveActivityScheduler {
    private struct ScheduleSnapshot: Sendable {
        let id: UUID
        let title: String
        let colorName: String?
        let kind: String
        let startAt: Date
        let endAt: Date?
    }

    /// Main sync — call on app foreground.
    /// Updates existing activities' phases, starts new ones, ends completed ones.
    static func sync(from schedules: [ScheduleDetail]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date.now
        let snapshots: [ScheduleSnapshot] = schedules
            .filter { !$0.isDone && $0.isActive }
            .compactMap { s in
                guard let startAt = s.startAt else { return nil }
                return ScheduleSnapshot(
                    id: s.id,
                    title: s.title,
                    colorName: s.color?.rawValue,
                    kind: s.kind == .task ? "task" : "event",
                    startAt: startAt,
                    endAt: s.endAt
                )
            }

        Task {
            var knownIDs: Set<UUID> = []

            for activity in Activity<MemdoScheduleAttributes>.activities {
                let id = activity.attributes.scheduleID
                guard let snap = snapshots.first(where: { $0.id == id }) else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    continue
                }
                knownIDs.insert(id)

                let currentPhase = activity.content.state.phase
                let targetPhase: MemdoScheduleAttributes.ScheduleState.Phase
                if let endAt = snap.endAt, endAt < now {
                    targetPhase = .done
                } else if snap.startAt <= now {
                    targetPhase = .ongoing
                } else {
                    targetPhase = .upcoming
                }

                if targetPhase == .done {
                    let doneState = makeState(snap: snap, phase: .done)
                    let dismissAt = now.addingTimeInterval(300)
                    await activity.end(
                        ActivityContent(state: doneState, staleDate: dismissAt),
                        dismissalPolicy: .after(dismissAt)
                    )
                } else if targetPhase != currentPhase {
                    let updatedState = makeState(snap: snap, phase: targetPhase)
                    let stale = staleDate(snap: snap)
                    await activity.update(ActivityContent(state: updatedState, staleDate: stale))
                }
            }

            // Start activities for eligible schedules not yet tracked
            for snap in snapshots where !knownIDs.contains(snap.id) {
                guard snap.startAt < now.addingTimeInterval(4 * 3600) else { continue }
                if let endAt = snap.endAt, endAt < now { continue }
                let phase: MemdoScheduleAttributes.ScheduleState.Phase = snap.startAt > now ? .upcoming : .ongoing
                _ = try? Activity<MemdoScheduleAttributes>.request(
                    attributes: MemdoScheduleAttributes(scheduleID: snap.id),
                    content: ActivityContent(state: makeState(snap: snap, phase: phase), staleDate: staleDate(snap: snap)),
                    pushType: nil
                )
            }
        }
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

    // MARK: Private helpers

    private static func makeState(
        snap: ScheduleSnapshot,
        phase: MemdoScheduleAttributes.ScheduleState.Phase
    ) -> MemdoScheduleAttributes.ScheduleState {
        MemdoScheduleAttributes.ScheduleState(
            title: snap.title,
            colorName: snap.colorName,
            kind: snap.kind,
            startAt: snap.startAt,
            endAt: snap.endAt,
            phase: phase
        )
    }

    private static func staleDate(snap: ScheduleSnapshot) -> Date {
        (snap.endAt ?? snap.startAt.addingTimeInterval(3600)).addingTimeInterval(300)
    }
}
