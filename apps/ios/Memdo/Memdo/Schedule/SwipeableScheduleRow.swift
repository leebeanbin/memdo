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
            SwipeActionButton(
                systemImage: schedule.isDone ? "arrow.uturn.backward" : "checkmark",
                tint: MemdoTheme.activityAccent,
                onTint: MemdoTheme.onActivityAccent,
                width: revealWidth,
                action: complete
            )
            .accessibilityHidden(true) // covered by the row-level accessibilityAction above
            .opacity(offset > 0 ? 1 : 0)

            Spacer(minLength: 0)

            SwipeActionButton(
                systemImage: "trash",
                tint: MemdoTheme.destructive,
                onTint: MemdoTheme.onDestructive,
                width: revealWidth,
                action: startDelete
            )
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

/// The revealed swipe action's tint used to fill only a fixed `touchTarget`
/// height, centered inside `SwipeableScheduleRow`'s full (usually taller,
/// two-line) row -- a floating colored box with visible background showing
/// above and below it instead of a solid fill. This fills the whole
/// available height instead, and adds the press feedback
/// (`MemdoActivityAccentButtonStyle`/`MemdoPrimaryActionButtonStyle`'s
/// opacity+scale convention) the bare Image-in-a-Button version had none of.
private struct SwipeActionButton: View {
    let systemImage: String
    let tint: Color
    let onTint: Color
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(MemdoTypography.title2)
                .fontWeight(.semibold)
        }
        .buttonStyle(SwipeActionButtonStyle(tint: tint, onTint: onTint, width: width))
    }
}

/// Same press feedback convention as `MemdoActivityAccentButtonStyle`
/// (Workout) / `MemdoPrimaryActionButtonStyle` -- opacity dim + slight
/// scale on press, respecting reduceMotion -- applied here via
/// `ButtonStyle.configuration.isPressed` rather than a manual gesture,
/// consistent with how every other button-press effect in this app is done.
private struct SwipeActionButtonStyle: ButtonStyle {
    let tint: Color
    let onTint: Color
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(onTint)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(tint)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.15), value: configuration.isPressed)
    }
}
