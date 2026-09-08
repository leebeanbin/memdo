import SwiftUI

/// Shared completion-toggle action for schedule-row call sites (swipe
/// actions, row checkboxes) -- was duplicated inline at each call site
/// (TodayView.toggleDone(_:) originally) as `Task { if let outcome =
/// try? await store.toggleDone(id:) { noticeCenter.reportWriteOutcome(outcome) } }`.
/// One implementation instead of several that could drift.
@MainActor
func toggleScheduleDone(
    _ schedule: ScheduleDetail,
    store: ScheduleStore,
    noticeCenter: AppNoticeCenter
) {
    Task {
        if let outcome = try? await store.toggleDone(id: schedule.id) {
            noticeCenter.reportWriteOutcome(outcome)
        }
    }
}
