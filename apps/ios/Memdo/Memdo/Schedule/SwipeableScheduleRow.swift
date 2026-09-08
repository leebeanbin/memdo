import SwiftUI

/// Wraps `ScheduleRow` with leading swipe-to-complete / trailing
/// swipe-to-delete, for the two `ScheduleRow` call sites that render
/// inside a plain `VStack`/`ForEach` rather than a `List` (a `List` row
/// gets this for free via native `.swipeActions` -- see
/// `CalendarView.DayAgendaSheet`, which uses that instead of this).
///
/// Reveal-then-tap, not full-swipe-auto-trigger: dragging past the snap
/// threshold reveals the action button, but it never fires without a
/// second, deliberate tap -- a fast or accidental swipe can't delete
/// something outright.
struct SwipeableScheduleRow: View {
    let schedule: ScheduleDetail
    let context: ScheduleRowContext
    let onOpen: () -> Void
    let onToggleDone: () -> Void
    @Binding var deleteTarget: ScheduleDetail?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    private let revealWidth: CGFloat = 76
    private var snapThreshold: CGFloat { revealWidth * 0.4 }

    var body: some View {
        ZStack {
            actionButtons
            ScheduleRow(schedule: schedule, context: context, onOpen: handleTap, onToggleDone: onToggleDone)
                .background(MemdoTheme.background)
                .offset(x: offset)
                .highPriorityGesture(dragGesture)
        }
        // Same two actions as the visible swipe buttons below, always
        // present regardless of gesture -- a VoiceOver user gets both via
        // the actions rotor without ever needing to drag anything (a
        // custom gesture like this has zero automatic VoiceOver support,
        // unlike native .swipeActions).
        .accessibilityAction(named: Text(schedule.isDone ? "완료 취소" : "완료로 표시")) { onToggleDone() }
        .accessibilityAction(named: Text("삭제")) { deleteTarget = schedule }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            Button(action: complete) {
                Image(systemName: schedule.isDone ? "arrow.uturn.backward" : "checkmark")
                    .font(MemdoTypography.title3)
                    .frame(width: revealWidth, height: MemdoMetrics.touchTarget)
                    .foregroundStyle(MemdoTheme.onActivityAccent)
            }
            .buttonStyle(.plain)
            .background(MemdoTheme.activityAccent)
            .accessibilityHidden(true) // covered by the row-level accessibilityAction above
            .opacity(offset > 0 ? 1 : 0)

            Spacer(minLength: 0)

            Button(role: .destructive, action: startDelete) {
                Image(systemName: "trash")
                    .font(MemdoTypography.title3)
                    .frame(width: revealWidth, height: MemdoMetrics.touchTarget)
                    .foregroundStyle(MemdoTheme.onDestructive)
            }
            .buttonStyle(.plain)
            .background(MemdoTheme.destructive)
            .accessibilityHidden(true)
            .opacity(offset < 0 ? 1 : 0)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(max(value.translation.width, -revealWidth), revealWidth)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(offset) > snapThreshold else {
                    snapClosed()
                    return
                }
                animate { offset = value.translation.width > 0 ? revealWidth : -revealWidth }
            }
    }

    private func handleTap() {
        if offset != 0 {
            snapClosed()
        } else {
            onOpen()
        }
    }

    private func complete() {
        onToggleDone()
        snapClosed()
    }

    private func startDelete() {
        deleteTarget = schedule
        snapClosed()
    }

    private func snapClosed() {
        animate { offset = 0 }
    }

    private func animate(_ body: () -> Void) {
        if reduceMotion {
            body()
        } else {
            withAnimation(.spring(duration: 0.25)) { body() }
        }
    }
}
