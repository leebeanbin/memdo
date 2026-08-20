import Foundation
import Security

/// Sends schedule events to a user-configured Slack Incoming Webhook.
/// All calls are fire-and-forget — failures are silently ignored to avoid
/// disrupting the primary save flow.
enum SlackNotifier {
    // A Slack Incoming Webhook URL is a bearer credential (anyone with it can
    // post to the user's channel) -- Keychain, not UserDefaults, matching
    // DeviceOnlyKeychainStorage's device-only, non-backed-up handling of the
    // Supabase session token elsewhere in this app.
    private static let service = "com.memdo.ios.slack"
    private static let account = "webhook-url"
    private static let legacyUserDefaultsKey = "slack-webhook-url"

    private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static var webhookURL: String {
        get {
            var lookup = query()
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data, let value = String(data: data, encoding: .utf8) {
                return value
            }
            // One-time migration: a value saved before this moved to Keychain
            // shouldn't silently vanish and look like the connection was lost.
            if let legacy = UserDefaults.standard.string(forKey: legacyUserDefaultsKey), !legacy.isEmpty {
                webhookURL = legacy
                UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
                return legacy
            }
            return ""
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
                SecItemDelete(query() as CFDictionary)
                return
            }
            var addQuery = query()
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            addQuery[kSecValueData as String] = data
            if SecItemAdd(addQuery as CFDictionary, nil) == errSecDuplicateItem {
                SecItemUpdate(query() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            }
        }
    }

    enum Event {
        case created, completed
    }

    /// Sends a one-off test message to verify a webhook URL works, distinct
    /// from `notify` (which is fire-and-forget and never surfaces failures --
    /// a user actively testing a connection needs to see whether it worked).
    /// Returns whether Slack responded 200; throws on a network/serialization
    /// failure so the caller can show that separately from "wrong URL."
    static func sendTest(to url: URL) async throws -> Bool {
        let payload = ["text": "✅ Memdo에서 보낸 테스트 메시지예요. 연결이 잘 됐어요!"]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
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
        }

        var parts = ["\(prefix): \(schedule.title)"]

        if let start = schedule.startAt {
            var time = DateFormatting.korean("M/d(E) a h:mm").string(from: start)
            if let end = schedule.endAt {
                time += " – \(DateFormatting.korean("h:mm").string(from: end))"
            }
            parts.append(time)
        } else {
            parts.append(DateFormatting.korean("M/d(E)").string(from: schedule.scheduledDate))
        }

        if let emoji = schedule.emoji, !emoji.isEmpty {
            parts[0] = "\(prefix): \(emoji) \(schedule.title)"
        }

        return parts.joined(separator: " | ")
    }
}
