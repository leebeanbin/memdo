import SwiftUI

enum ScheduleRowContext {
    case timeline
    case dated
}

struct ScheduleRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let schedule: ScheduleDetail
    let context: ScheduleRowContext
    let onOpen: (() -> Void)?
    var onToggleDone: (() -> Void)?

    init(
        schedule: ScheduleDetail,
        context: ScheduleRowContext,
        onOpen: (() -> Void)? = nil,
        onToggleDone: (() -> Void)? = nil
    ) {
        self.schedule = schedule
        self.context = context
        self.onOpen = onOpen
        self.onToggleDone = onToggleDone
    }

    var body: some View {
        HStack(spacing: MemdoMetrics.rowSpacing) {
            leadingMarker

            if let onOpen {
                Button(action: onOpen) { rowContent }
                    .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .padding(.horizontal, MemdoMetrics.rowInset)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingMarker: some View {
        if schedule.kind == .task {
            if let onToggleDone {
                Button(action: onToggleDone) {
                    Image(systemName: schedule.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(schedule.isDone ? MemdoTheme.secondaryInk : MemdoTheme.brand)
                        .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(schedule.isDone ? "완료 취소" : "완료로 표시")
            } else {
                Image(systemName: schedule.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(schedule.isDone ? MemdoTheme.secondaryInk : MemdoTheme.brand)
                    .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                    .accessibilityHidden(true)
            }
        } else if context == .timeline && !dynamicTypeSize.isAccessibilitySize {
            EventTimeMarker(schedule: schedule)
        } else {
            Image(systemName: schedule.isExternal ? "calendar" : "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                .accessibilityHidden(true)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if context == .dated || dynamicTypeSize.isAccessibilitySize {
                    Text(context == .dated ? "\(schedule.dateText) · \(schedule.displayTime)" : schedule.displayTime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                HStack(spacing: 4) {
                    if let provider = schedule.meetingProvider {
                        Image(systemName: provider.systemImage)
                            .font(.caption2)
                            .foregroundStyle(MemdoTheme.brand)
                            .accessibilityLabel("\(provider.label) 회의")
                    }
                    if schedule.scheduleRuleId != nil {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                            .accessibilityLabel("반복 일정")
                    }
                    Text(schedule.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .strikethrough(schedule.isDone)
                        .foregroundStyle(schedule.isDone ? MemdoTheme.secondaryInk : MemdoTheme.ink)
                }

                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if onOpen != nil && !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var metadata: String {
        let timing: String
        if schedule.kind == .event {
            timing = schedule.isAllDay ? "종일" : "시간 일정"
        } else if let due = schedule.dueTimeText {
            timing = "마감 \(due)"
        } else {
            timing = "할 일 · \(schedule.startTimeText)"
        }
        return schedule.isExternal
            ? "\(timing) · \(schedule.calendar.title)"
            : "\(timing) · \(schedule.calendar.title) · \(schedule.source)"
    }
}

private struct EventTimeMarker: View {
    let schedule: ScheduleDetail

    var body: some View {
        Group {
            if schedule.isAllDay {
                Text("종일")
                    .font(.caption2.weight(.semibold))
            } else {
                VStack(spacing: 4) {
                    Text(schedule.startTimeText)
                    Capsule()
                        .fill(MemdoTheme.controlOutline)
                        .frame(width: 1, height: 8)
                    Text(schedule.endTimeText)
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
            }
        }
        .foregroundStyle(MemdoTheme.secondaryInk)
        .frame(width: MemdoMetrics.rowLeadingWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(schedule.displayTime)
    }
}

struct ScheduleSourceIcon: View {
    let schedule: ScheduleDetail

    var body: some View {
        Image(systemName: schedule.kind == .task ? "checkmark" : schedule.isExternal ? "calendar" : "clock")
            .font(.caption.weight(.bold))
            .foregroundStyle(schedule.kind == .task ? MemdoTheme.brand : MemdoTheme.secondaryInk)
            .frame(width: 30, height: 30)
            .background(
                MemdoTheme.accentSoft,
                in: RoundedRectangle(cornerRadius: MemdoMetrics.iconRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
