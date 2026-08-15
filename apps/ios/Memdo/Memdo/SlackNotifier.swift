import Foundation

/// Sends schedule events to a user-configured Slack Incoming Webhook.
/// All calls are fire-and-forget — failures are silently ignored to avoid
/// disrupting the primary save flow.
enum SlackNotifier {
    private static let webhookKey = "slack-webhook-url"

    static var webhookURL: String {
        get { UserDefaults.standard.string(forKey: webhookKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: webhookKey) }
    }

    enum Event {
        case created, completed, reminder
    }

    static func notify(schedule: ScheduleDetail, event: Event) async {
        let urlString = webhookURL
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }

        let text = message(for: schedule, event: event)
        guard let body = try? JSONSerialization.data(withJSONObject: ["text": text]) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 8

        _ = try? await URLSession.shared.data(for: request)
    }

    private static func message(for schedule: ScheduleDetail, event: Event) -> String {
        let prefix: String
        switch event {
        case .created:   prefix = "📅 새 일정"
        case .completed: prefix = "✅ 완료"
        case .reminder:  prefix = "⏰ 리마인더"
        }

        var parts = ["\(prefix): \(schedule.title)"]

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M/d(E) a h:mm"

        if let start = schedule.startAt {
            var time = fmt.string(from: start)
            if let end = schedule.endAt {
                let endFmt = DateFormatter()
                endFmt.locale = Locale(identifier: "ko_KR")
                endFmt.dateFormat = "h:mm"
                time += " – \(endFmt.string(from: end))"
            }
            parts.append(time)
        } else {
            let dayFmt = DateFormatter()
            dayFmt.locale = Locale(identifier: "ko_KR")
            dayFmt.dateFormat = "M/d(E)"
            parts.append(dayFmt.string(from: schedule.scheduledDate))
        }

        if let emoji = schedule.emoji, !emoji.isEmpty {
            parts[0] = "\(prefix): \(emoji) \(schedule.title)"
        }

        return parts.joined(separator: " | ")
    }
}
