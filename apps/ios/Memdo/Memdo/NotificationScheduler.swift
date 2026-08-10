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
        let status = await center.notificationSettings().authorizationStatus
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
