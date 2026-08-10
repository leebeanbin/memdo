import AppIntents

// Publishing App Intents makes Memdo a building block for Siri, Apple
// Intelligence multi-app workflows, and user-authored Shortcuts (iOS 27 routes
// third-party app actions exclusively through App Intents).

/// Opens Memdo's quick-add capture flow. An optional text parameter lets Siri /
/// Shortcuts hand off content (a pasted link, an invite) to pre-fill.
struct CaptureEventIntent: AppIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "붙여넣어 일정 만들기"
    static let description = IntentDescription("링크나 초대 내용을 붙여넣어 일정 초안을 만듭니다.")
    static let openAppWhenRun = true

    @Parameter(title: "내용")
    var text: String?

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct MemdoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureEventIntent(),
            phrases: [
                "\(.applicationName)에 일정 추가",
                "Add an event to \(.applicationName)"
            ],
            shortTitle: "일정 추가",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: GenerateWallpaperIntent(),
            phrases: [
                "\(.applicationName) 달력 배경화면 만들기",
                "Make a calendar wallpaper with \(.applicationName)"
            ],
            shortTitle: "달력 배경화면",
            systemImageName: "photo.on.rectangle"
        )
    }
}
