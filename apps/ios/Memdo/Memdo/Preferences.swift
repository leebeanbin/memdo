import Foundation
import Observation
import Supabase

/// User settings persisted to the backend `/preferences` endpoint (full-object upsert).
/// The client only exposes a subset in the UI, so unchanged fields must round-trip
/// verbatim: always GET the full object, mutate a few fields, then PUT it back.
struct UserPreferences: Equatable {
    /// Optimistic-concurrency token (bd19) -- threaded from the last GET/PUT
    /// response back into the next PUT's request body, the same way
    /// ScheduleDetail.version is threaded through schedule writes. The
    /// server rejects a PUT whose updatedAt doesn't match its current row.
    var updatedAt: String
    var timezone: String
    var widgetStyle: String
    var defaultMood: String?
    var hideWidgetContent: Bool
    var notificationsEnabled: Bool
    var planningPromptTime: String?
    var quietHoursStart: String?
    var quietHoursEnd: String?
    var calendarFilter: [String]
    var dailyReviewEnabled: Bool
    var dailyReviewTime: String?
    var dailyReviewDays: [String]
    var dailyReviewIncludeReflection: Bool
    var newsBriefingEnabled: Bool
    var newsBriefingTime: String?
    var newsBriefingDays: [String]

    static let allWeekdays = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
}

/// Converts between a `Date` (hour/minute only) and the backend "HH:mm" local time string.
enum ClockString {
    static func from(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(from: DateComponents(hour: parts[0], minute: parts[1]))
    }
}

struct PreferencesResponseDTO: Decodable {
    struct Review: Decodable {
        let enabled: Bool
        let time: String?
        let days: [String]
        let includeReflection: Bool
    }

    struct Briefing: Decodable {
        let enabled: Bool
        let time: String?
        let days: [String]
    }

    let updatedAt: String
    let timezone: String
    let widgetStyle: String
    let defaultMood: String?
    let hideWidgetContent: Bool
    let notificationsEnabled: Bool
    let planningPromptTime: String?
    let quietHoursStart: String?
    let quietHoursEnd: String?
    let calendarFilter: [String]
    let dailyReview: Review
    let newsBriefing: Briefing

    var model: UserPreferences {
        UserPreferences(
            updatedAt: updatedAt,
            timezone: timezone,
            widgetStyle: widgetStyle,
            defaultMood: defaultMood,
            hideWidgetContent: hideWidgetContent,
            notificationsEnabled: notificationsEnabled,
            planningPromptTime: planningPromptTime,
            quietHoursStart: quietHoursStart,
            quietHoursEnd: quietHoursEnd,
            calendarFilter: calendarFilter,
            dailyReviewEnabled: dailyReview.enabled,
            dailyReviewTime: dailyReview.time,
            dailyReviewDays: dailyReview.days,
            dailyReviewIncludeReflection: dailyReview.includeReflection,
            newsBriefingEnabled: newsBriefing.enabled,
            newsBriefingTime: newsBriefing.time,
            newsBriefingDays: newsBriefing.days
        )
    }
}

struct PreferencesInputDTO: Encodable {
    struct Review: Encodable {
        let enabled: Bool
        let time: String?
        let days: [String]
        let includeReflection: Bool
    }

    struct Briefing: Encodable {
        let enabled: Bool
        let time: String?
        let days: [String]
    }

    let updatedAt: String
    let timezone: String
    let widgetStyle: String
    let defaultMood: String?
    let hideWidgetContent: Bool
    let notificationsEnabled: Bool
    let planningPromptTime: String?
    let quietHoursStart: String?
    let quietHoursEnd: String?
    let calendarFilter: [String]
    let dailyReview: Review
    let newsBriefing: Briefing

    init(_ preferences: UserPreferences) {
        updatedAt = preferences.updatedAt
        timezone = preferences.timezone
        widgetStyle = preferences.widgetStyle
        defaultMood = preferences.defaultMood
        hideWidgetContent = preferences.hideWidgetContent
        notificationsEnabled = preferences.notificationsEnabled
        planningPromptTime = preferences.planningPromptTime
        quietHoursStart = preferences.quietHoursStart
        quietHoursEnd = preferences.quietHoursEnd
        calendarFilter = preferences.calendarFilter
        dailyReview = Review(
            enabled: preferences.dailyReviewEnabled,
            time: preferences.dailyReviewTime,
            days: preferences.dailyReviewDays,
            includeReflection: preferences.dailyReviewIncludeReflection
        )
        newsBriefing = Briefing(
            enabled: preferences.newsBriefingEnabled,
            time: preferences.newsBriefingTime,
            days: preferences.newsBriefingDays
        )
    }
}

extension MemdoAPIClient {
    func preferences(accessToken: String) async throws -> PreferencesResponseDTO {
        try await send(path: "preferences", accessToken: accessToken)
    }

    func updatePreferences(
        _ input: PreferencesInputDTO,
        idempotencyKey: UUID,
        accessToken: String
    ) async throws -> PreferencesResponseDTO {
        try await send(
            path: "preferences",
            method: "PUT",
            body: JSONEncoder().encode(input),
            idempotencyKey: idempotencyKey,
            accessToken: accessToken
        )
    }
}

actor PreferencesRepository {
    private let auth: SupabaseClient
    private let api: MemdoAPIClient

    init(configuration: MemdoConfiguration, auth: SupabaseClient) {
        self.auth = auth
        api = MemdoAPIClient(
            projectURL: configuration.projectURL,
            publishableKey: configuration.publishableKey
        )
    }

    func load() async throws -> UserPreferences {
        try await api.preferences(accessToken: accessToken()).model
    }

    func save(_ preferences: UserPreferences) async throws -> UserPreferences {
        try await api.updatePreferences(
            PreferencesInputDTO(preferences),
            idempotencyKey: UUID(),
            accessToken: accessToken()
        ).model
    }

    private func accessToken() async throws -> String {
        guard auth.auth.currentSession != nil else { throw ScheduleAPIError.notAuthenticated }
        return try await auth.auth.session.accessToken
    }
}

@MainActor
@Observable
final class PreferencesStore {
    private(set) var preferences: UserPreferences?
    private let repository: PreferencesRepository
    /// Load/save failures post here as a dismissible, non-blocking notice --
    /// Settings must stay usable even offline.
    private let noticeCenter: AppNoticeCenter

    init(repository: PreferencesRepository, noticeCenter: AppNoticeCenter = AppNoticeCenter()) {
        self.repository = repository
        self.noticeCenter = noticeCenter
    }

    func load() async {
        do {
            preferences = try await repository.load()
        } catch {
            noticeCenter.error(error.localizedDescription)
        }
    }

    func reset() {
        preferences = nil
    }

    /// Mutates the cached full object and persists it. Loads first if nothing is
    /// cached yet (rather than silently dropping the change), since untouched
    /// server fields must round-trip through the full-object upsert.
    ///
    /// Returns whether the save actually succeeded -- `false` on a load
    /// failure (nothing to update) or a save failure (previous value is
    /// restored, same as before). `@discardableResult` so existing fire-and-
    /// forget call sites (SettingsView, MemdoGuideSheet) keep compiling and
    /// behaving identically. Callers that need to know whether their change
    /// actually persisted (e.g. an Agent proposal approval, which shouldn't
    /// tell the user something was applied when it wasn't) inspect the
    /// return value.
    ///
    /// `notify` gates only the success notice -- a failure always posts one.
    /// Defaults to `false`: every current caller is an ambient auto-save
    /// (a toggle flip, a debounced time-picker push), and a toast firing on
    /// every one of those would be noisy and inconsistent with standard iOS
    /// Settings UX, where the control's own state is the confirmation. Pass
    /// `true` only for a distinct, user-initiated save action that should get
    /// its own confirmation.
    @discardableResult
    func update(_ transform: (inout UserPreferences) -> Void, notify: Bool = false) async -> Bool {
        if preferences == nil {
            await load()
        }
        guard var updated = preferences else { return false }
        let previous = preferences
        transform(&updated)
        preferences = updated
        do {
            preferences = try await repository.save(updated)
            if notify { noticeCenter.success("설정을 저장했어요.") }
            return true
        } catch {
            preferences = previous
            noticeCenter.error(error.localizedDescription)
            return false
        }
    }
}
