import Foundation

/// A model-supplied date token ("today" | "tomorrow" | "yyyy-MM-dd"),
/// resolved and validated in one step. Shared by the on-device Tools
/// (ProposeScheduleTool/FindFreeSlotTool/UpdateScheduleTool) and the cloud
/// staging path in AssistantView.swift, so both trust boundaries reject the
/// same malformed tokens the same way.
enum AgentDateExpression: Equatable {
    case today, tomorrow, yesterday, explicit(Date)

    /// nil means the model produced a token that isn't "today", "tomorrow",
    /// "yesterday", or a real yyyy-MM-dd calendar date -- callers must treat
    /// that as an explicit failure (reject the call, don't stage anything)
    /// rather than falling back to "today". `DateFormatting.posix`'s
    /// `DateFormatter` has `isLenient == false` by default, so an impossible
    /// date like "2026-02-31" already returns nil here without any extra
    /// configuration.
    init?(token: String) {
        switch token {
        case "today": self = .today
        case "tomorrow": self = .tomorrow
        case "yesterday": self = .yesterday
        default:
            guard let date = DateFormatting.posix("yyyy-MM-dd").date(from: token) else { return nil }
            self = .explicit(date)
        }
    }

    /// Total, not failable -- by the time a value exists, `init?` has
    /// already rejected anything unparseable. The `?? .now` fallbacks below
    /// are NOT a model-output boundary: they cover `Calendar.date(byAdding:)`
    /// returning nil, which in practice doesn't happen for a same-day ±1
    /// offset. Model-produced invalid tokens are rejected earlier, at
    /// `init?` -- this distinction (pragmatic internal-arithmetic fallback
    /// vs. never-fallback-on-model-output) is deliberate, not an oversight.
    func resolvedDate(calendar: Calendar = .current) -> Date {
        switch self {
        case .today: calendar.startOfDay(for: .now)
        case .tomorrow: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        case .yesterday: calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now)
        case .explicit(let date): calendar.startOfDay(for: date)
        }
    }
}

/// A model-supplied propose_schedule_update action, validated against the
/// fixed set the backend's proposeScheduleUpdateArgsSchema also enforces.
enum AgentUpdateAction: String {
    case complete, reschedule, delete
}
