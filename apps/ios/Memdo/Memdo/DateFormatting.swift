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
}
