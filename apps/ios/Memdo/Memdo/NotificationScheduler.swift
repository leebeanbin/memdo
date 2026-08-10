import Foundation
import UIKit
import UserNotifications

// MARK: - Scheduler

enum NotificationScheduler {
    private static let planningID = "memdo.planning-prompt"
    private static let reviewPrefix = "memdo.daily-review-"

    /// Requests authorization if not yet determined; returns whether notifications
    /// are authorized (or provisional). Call when the user enables the toggle.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        return status == .authorized || status == .provisional
    }

    /// Rebuilds all Memdo notifications from the current preferences.
    /// Cancels everything if `notificationsEnabled` is false or permission is missing.
    static func schedule(for preferences: UserPreferences) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus

        // First launch: notifications are enabled by default but permission was
        // never explicitly requested. Request it now so scheduling can proceed.
        if preferences.notificationsEnabled && status == .notDetermined {
            _ = await requestPermission()
            status = await center.notificationSettings().authorizationStatus
        }

        guard preferences.notificationsEnabled,
              status == .authorized || status == .provisional
        else {
            await cancelAll()
            return
        }
        await cancelAll()
        await schedulePlanningPrompt(preferences, center: center)
        await scheduleDailyReview(preferences, center: center)
    }

    /// Removes every pending Memdo notification without touching non-Memdo ones.
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("memdo.") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: Private

    private static func schedulePlanningPrompt(
        _ preferences: UserPreferences,
        center: UNUserNotificationCenter
    ) async {
        guard let time = ClockString.date(preferences.planningPromptTime) else { return }

        let content = UNMutableNotificationContent()
        content.title = "오늘 계획을 세울 시간이에요"
        content.body = "Memdo를 열어 오늘 일정을 정리해보세요"
        content.sound = .default
        content.userInfo = ["memdo_link": "today"]

        var components = Calendar.current.dateComponents([.hour, .minute], from: time)
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: planningID, content: content, trigger: trigger))
    }

    private static func scheduleDailyReview(
        _ preferences: UserPreferences,
        center: UNUserNotificationCenter
    ) async {
        guard preferences.dailyReviewEnabled,
              let time = ClockString.date(preferences.dailyReviewTime) else { return }

        let days = preferences.dailyReviewDays.isEmpty ? UserPreferences.allWeekdays : preferences.dailyReviewDays
        var timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
        timeComponents.second = 0

        for day in days {
            guard let weekday = weekdayIndex(day) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "하루를 돌아볼 시간이에요"
            content.body = "오늘 일정 결과를 확인하고 내일을 준비해보세요"
            content.sound = .default
            content.userInfo = ["memdo_link": "summary"]

            var trigger = timeComponents
            trigger.weekday = weekday
            try? await center.add(UNNotificationRequest(
                identifier: "\(reviewPrefix)\(day)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true)
            ))
        }
    }

    private static func weekdayIndex(_ code: String) -> Int? {
        switch code {
        case "SU": 1; case "MO": 2; case "TU": 3; case "WE": 4
        case "TH": 5; case "FR": 6; case "SA": 7; default: nil
        }
    }

    // MARK: - Per-schedule reminders

    /// Cancels any existing reminder for `schedule` and schedules a fresh one
    /// when the schedule has a future start time and a reminder offset.
    /// Idempotent — safe to call on every save.
    static func scheduleReminder(for schedule: ScheduleDetail) async {
        let center = UNUserNotificationCenter.current()
        let id = reminderID(for: schedule.id)
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard let offsetMinutes = schedule.reminderOffsetMinutes,
              let startAt = schedule.startAt,
              schedule.isActive,
              !schedule.isDone
        else { return }

        let fireAt = startAt.addingTimeInterval(-Double(offsetMinutes) * 60)
        guard fireAt > .now else { return }

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = schedule.emoji.map { "\($0) \(schedule.title)" } ?? schedule.title
        content.body = reminderBody(offset: offsetMinutes)
        content.sound = .default
        content.userInfo = ["memdo_link": "today"]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Removes the pending reminder for a specific schedule.
    static func cancelReminder(for scheduleID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID(for: scheduleID)])
    }

    private static func reminderID(for id: UUID) -> String {
        "memdo.reminder-\(id.uuidString.lowercased())"
    }

    private static func reminderBody(offset: Int) -> String {
        switch offset {
        case 0: return "지금 시작해요"
        case 1..<60: return "\(offset)분 후 시작해요"
        case 60: return "1시간 후 시작해요"
        case 61..<1440:
            let h = offset / 60, m = offset % 60
            return m == 0 ? "\(h)시간 후 시작해요" : "\(h)시간 \(m)분 후 시작해요"
        default: return "내일 시작해요"
        }
    }
}

// MARK: - Delegate

/// Routes notification taps to Memdo deep links and shows banners in-foreground.
final class MemdoNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = MemdoNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let link = response.notification.request.content.userInfo["memdo_link"] as? String,
           let url = URL(string: "memdo://\(link)") {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
