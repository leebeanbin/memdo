import Foundation

/// Centralizes the two `DateFormatter` locale patterns that were repeated
/// at every date-formatting call site across the app (SlackNotifier,
/// AssistantView, NotificationScheduler, BriefingFeed) instead of each one
/// constructing its own formatter and setting the same locale by hand:
/// - `korean(_:)` for user-facing display text (weekday names, "월/일" etc).
/// - `posix(_:)` for machine-readable formats (yyyy-MM-dd tokens, RFC 2822
///   parsing) where the *device's* locale/calendar must never affect the
///   result -- `en_US_POSIX` is Apple's documented fix for DateFormatter's
///   locale-dependent parsing of otherwise-fixed formats.
enum DateFormatting {
    static func korean(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format
        return formatter
    }

    static func posix(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    /// Cached, MainActor-isolated formatters for the few call sites that
    /// read one on every SwiftUI render (day-timeline rows, the Today tab's
    /// date subtitle) -- `korean(_:)`/`posix(_:)` above still allocate a
    /// fresh `DateFormatter` per call, which is fine for occasional use but
    /// was measurable on those hot paths. `@MainActor` rather than a plain
    /// `static let` since `DateFormatter` isn't `Sendable`; every current
    /// caller already runs on the main actor (SwiftUI view code), so this
    /// isn't a new constraint, just making the existing implicit one
    /// explicit.
    @MainActor
    enum Cached {
        static let monthDayWeekday = DateFormatting.korean("M월 d일 EEEE")
        static let monthDayTime = DateFormatting.korean("M월 d일 a h:mm")
        static let fullDate = DateFormatting.korean("yyyy년 M월 d일 EEEE")
        static let timelineHourMinute = DateFormatter.build("H:mm")
    }
}

private extension DateFormatter {
    static func build(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter
    }
}
