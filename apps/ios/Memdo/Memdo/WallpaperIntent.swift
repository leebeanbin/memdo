import AppIntents
import SwiftUI
import UniformTypeIdentifiers

/// Generates the full-calendar lock-screen image so a Shortcuts automation can
/// pipe it into the system "Set Wallpaper Photo" action (e.g. every morning).
/// Reads the widget snapshot instead of ScheduleStore so it works offline and
/// without a signed-in UI session, and reuses the styling last chosen in the
/// in-app preview.
struct GenerateWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "달력 배경화면 만들기"
    static let description = IntentDescription(
        "이번 달 일정이 담긴 잠금화면 달력 이미지를 만듭니다. ‘배경화면 사진 설정’ 액션에 연결하면 매일 자동으로 갱신할 수 있어요."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let defaults = UserDefaults(suiteName: MemdoWidgetStorage.suiteName)
        let snapshot = defaults?.data(forKey: MemdoWidgetStorage.snapshotKey)
            .flatMap { try? JSONDecoder().decode(MemdoWidgetSnapshot.self, from: $0) }
            ?? .empty(at: .now)
        let hidesContent = defaults?.bool(forKey: MemdoWidgetStorage.hideContentKey) ?? false

        func style<Style: RawRepresentable>(_ key: String, default fallback: Style) -> Style
        where Style.RawValue == String {
            defaults?.string(forKey: key).flatMap(Style.init(rawValue:)) ?? fallback
        }

        guard let image = WallpaperImageExporter.uiImage(
            month: .now,
            titlesByDay: WallpaperCanvas.titles(from: snapshot, month: .now, hidesContent: hidesContent),
            calendarStyle: style(WallpaperStyleStorage.calendarKey, default: .label),
            backdrop: style(WallpaperStyleStorage.backdropKey, default: .aurora),
            glassStrength: style(WallpaperStyleStorage.glassKey, default: .balanced)
        ), let data = image.pngData() else {
            throw GenerateWallpaperError.renderingFailed
        }

        return .result(
            value: IntentFile(data: data, filename: "memdo-calendar-wallpaper.png", type: .png)
        )
    }
}

enum GenerateWallpaperError: Error, CustomLocalizedStringResourceConvertible {
    case renderingFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .renderingFailed: "달력 이미지를 만들지 못했어요. Memdo를 한 번 열어 일정을 동기화한 뒤 다시 시도해 주세요."
        }
    }
}
