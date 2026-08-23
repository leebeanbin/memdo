import Foundation
import Yams

/// Central loader for `Resources/Prompts/AgentPrompts.yml` -- the single
/// source of truth for the on-device Agent's system instructions, every
/// "빠른 요청" quick-action label/prompt, and the briefing feature's two
/// on-device rewrite instructions. See that file's header comment for the
/// full rationale.
enum AgentPrompts {
    struct QuickAction: Decodable {
        let label: String
        let prompt: String
    }

    private struct File: Decodable {
        struct OnDeviceAgent: Decodable { let instructions: String }
        struct QuickActions: Decodable {
            let calendar: [QuickAction]
            let review: [QuickAction]
            let settings: [QuickAction]
            let todayEmpty: [QuickAction]
            let today: [QuickAction]
            enum CodingKeys: String, CodingKey {
                case calendar, review, settings, today
                case todayEmpty = "today_empty"
            }
        }
        struct Briefing: Decodable {
            let headlineInstructions: String
            let cleanupInstructions: String
            enum CodingKeys: String, CodingKey {
                case headlineInstructions = "headline_instructions"
                case cleanupInstructions = "cleanup_instructions"
            }
        }
        let onDeviceAgent: OnDeviceAgent
        let quickActions: QuickActions
        let briefing: Briefing
        enum CodingKeys: String, CodingKey {
            case onDeviceAgent = "on_device_agent"
            case quickActions = "quick_actions"
            case briefing
        }
    }

    // A decode failure here means the bundled resource is missing or
    // malformed -- a packaging/build bug, not a runtime condition to
    // recover from, so this fails loudly rather than silently degrading
    // every Agent prompt in the app.
    private static let file: File = {
        guard let url = Bundle.main.url(forResource: "AgentPrompts", withExtension: "yml"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let decoded = try? YAMLDecoder().decode(File.self, from: text)
        else {
            fatalError("AgentPrompts.yml is missing or malformed in the app bundle")
        }
        return decoded
    }()

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var onDeviceInstructions: String { trimmed(file.onDeviceAgent.instructions) }
    static var briefingHeadlineInstructions: String { trimmed(file.briefing.headlineInstructions) }
    static var briefingCleanupInstructions: String { trimmed(file.briefing.cleanupInstructions) }

    /// Quick-action (label, prompt) pairs for the given Agent context.
    /// `{context}` in a review prompt is replaced with `context.displayTitle`.
    static func quickActions(for context: AgentContext, hasSchedulesToday: Bool) -> [(String, String)] {
        let actions: [QuickAction]
        switch context {
        case .calendar:
            actions = file.quickActions.calendar
        case .todaySummary, .weekReview, .monthReview:
            return file.quickActions.review.map {
                ($0.label, $0.prompt.replacingOccurrences(of: "{context}", with: context.displayTitle))
            }
        case .settings:
            actions = file.quickActions.settings
        case .today:
            actions = hasSchedulesToday ? file.quickActions.today : file.quickActions.todayEmpty
        }
        return actions.map { ($0.label, $0.prompt) }
    }
}
