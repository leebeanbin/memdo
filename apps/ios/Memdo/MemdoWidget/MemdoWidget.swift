import AppIntents
import SwiftUI
import WidgetKit

private enum MemdoWidgetTheme {
    static let background = Color(uiColor: .systemBackground)
    static let accent = Color(uiColor: .label)
    static let onAccent = Color(uiColor: .systemBackground)
}

struct MemdoWidgetEntry: TimelineEntry {
    let date: Date
    let items: [MemdoWidgetItem]
}

private struct MemdoWidgetSnapshot: Codable {
    let updatedAt: Date
    let items: [MemdoWidgetItem]
}

struct MemdoWidgetItem: Codable, Hashable {
    let time: String
    let title: String
}

private func loadScheduleItems() -> [MemdoWidgetItem] {
    guard let data = UserDefaults(suiteName: "group.com.memdo.ios")?
        .data(forKey: "today-schedule-snapshot") else { return [] }
    return (try? JSONDecoder().decode(MemdoWidgetSnapshot.self, from: data).items) ?? []
}

struct MemdoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemdoWidgetEntry {
        MemdoWidgetEntry(date: .now, items: loadScheduleItems())
    }

    func getSnapshot(in context: Context, completion: @escaping (MemdoWidgetEntry) -> Void) {
        completion(MemdoWidgetEntry(date: .now, items: loadScheduleItems()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemdoWidgetEntry>) -> Void) {
        completion(Timeline(
            entries: [MemdoWidgetEntry(date: .now, items: loadScheduleItems())],
            policy: .after(.now.addingTimeInterval(900))
        ))
    }
}

struct MemdoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MemdoWidgetEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(inlineText, systemImage: "calendar")
        case .accessoryCircular:
            VStack(spacing: -2) {
                Text(entry.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2)
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.title2.bold())
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(entry.date.formatted(.dateTime.month().day())) · \(entry.items.count)개", systemImage: "calendar")
                    .font(.caption.bold())
                    .widgetAccentable()
                compactItems(limit: 2)
            }
            .font(.caption)
        case .systemMedium:
            HStack(spacing: 16) {
                WidgetWeek(date: entry.date)
                    .frame(width: 130)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("오늘 일정").font(.headline)
                    scheduleItems(limit: 3)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.date.formatted(.dateTime.month(.wide))).font(.caption2)
                        Text(entry.date.formatted(.dateTime.day()))
                            .font(.title.bold())
                            .foregroundStyle(MemdoWidgetTheme.accent)
                    }
                    Spacer()
                    Label("\(entry.items.count)개", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                scheduleItems(limit: 2)
                Spacer(minLength: 0)
            }
            .padding(4)
        }
    }

    private var inlineText: String {
        guard let first = entry.items.first else { return "오늘 일정 없음" }
        let remaining = entry.items.count - 1
        return "\(first.time) \(first.title)\(remaining > 0 ? " · +\(remaining)" : "")"
    }

    @ViewBuilder
    private func compactItems(limit: Int) -> some View {
        if entry.items.isEmpty {
            Text("앱을 열어 일정을 동기화하세요").foregroundStyle(.secondary)
        } else {
            ForEach(Array(entry.items.prefix(limit)), id: \.self) { item in
                Text("\(item.time)  \(item.title)").lineLimit(1)
            }
            if entry.items.count > limit {
                Text("+\(entry.items.count - limit)개 더").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func scheduleItems(limit: Int) -> some View {
        if entry.items.isEmpty {
            Text("일정 없음").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(Array(entry.items.prefix(limit)), id: \.self) { item in
                WidgetTask(icon: "calendar", time: item.time, title: item.title)
            }
            if entry.items.count > limit {
                Text("+\(entry.items.count - limit)개 더")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WidgetTask: View {
    let icon: String
    let time: String
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .frame(width: 12)
            Text(time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct WidgetWeek: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(date.formatted(.dateTime.month(.wide))).font(.headline)
            HStack(spacing: 4) {
                ForEach(weekDates, id: \.self) { date in
                    let isToday = Calendar.current.isDateInToday(date)
                    VStack(spacing: 4) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption2)
                        Text(date.formatted(.dateTime.day())).font(.caption.bold())
                    }
                    .foregroundStyle(isToday ? MemdoWidgetTheme.onAccent : .primary)
                    .frame(width: 22, height: 42)
                    .background(
                        isToday ? MemdoWidgetTheme.accent : Color.clear,
                        in: Capsule()
                    )
                }
            }
            Text("오늘")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

struct MemdoTodayWidget: Widget {
    let kind = "MemdoTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemdoWidgetProvider()) { entry in
            MemdoWidgetView(entry: entry)
                .containerBackground(
                    MemdoWidgetTheme.background,
                    for: .widget
                )
                .widgetURL(URL(string: "memdo://today"))
        }
        .configurationDisplayName("오늘의 Memdo")
        .description("잠금화면에서 오늘의 일정을 확인합니다.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall,
            .systemMedium
        ])
    }
}

enum CalendarWidgetRange: String, AppEnum {
    case week
    case month

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "달력 범위")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .week: "일주일",
        .month: "한 달"
    ]
}

struct CalendarWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "달력 설정"
    static let description = IntentDescription("위젯에 표시할 달력 범위를 선택합니다.")

    @Parameter(title: "보기", default: .week)
    var range: CalendarWidgetRange
}

struct CalendarWidgetEntry: TimelineEntry {
    let date: Date
    let range: CalendarWidgetRange
    let items: [MemdoWidgetItem]
}

struct CalendarWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CalendarWidgetEntry {
        CalendarWidgetEntry(date: .now, range: .week, items: loadScheduleItems())
    }

    func snapshot(for configuration: CalendarWidgetConfigurationIntent, in context: Context) async -> CalendarWidgetEntry {
        CalendarWidgetEntry(date: .now, range: configuration.range, items: loadScheduleItems())
    }

    func timeline(for configuration: CalendarWidgetConfigurationIntent, in context: Context) async -> Timeline<CalendarWidgetEntry> {
        let entry = CalendarWidgetEntry(date: .now, range: configuration.range, items: loadScheduleItems())
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        return Timeline(entries: [entry], policy: .after(nextDay))
    }
}

struct MemdoCalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarWidgetEntry

    var body: some View {
        switch entry.range {
        case .week:
            week
        case .month:
            month
        }
    }

    private var week: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.date.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            HStack(spacing: 4) {
                ForEach(weekDates, id: \.self) { date in
                    let isToday = Calendar.current.isDateInToday(date)
                    VStack(spacing: 4) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                        Text(date.formatted(.dateTime.day()))
                            .font(.caption.bold())
                    }
                    .foregroundStyle(isToday ? MemdoWidgetTheme.onAccent : .primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(isToday ? MemdoWidgetTheme.accent : .clear, in: Capsule())
                }
            }
            Divider()
            agenda(limit: 3)
        }
        .padding(4)
    }

    private var month: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.date.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) {
                    Text($0)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                ForEach(monthDates.indices, id: \.self) { index in
                    if let date = monthDates[index] {
                        let isToday = Calendar.current.isDateInToday(date)
                        Text(date.formatted(.dateTime.day()))
                            .font(.caption2.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? MemdoWidgetTheme.onAccent : .primary)
                            .frame(maxWidth: .infinity, minHeight: family == .systemLarge ? 28 : 20)
                            .background(isToday ? MemdoWidgetTheme.accent : .clear, in: Circle())
                    } else {
                        Color.clear.frame(height: family == .systemLarge ? 28 : 20)
                    }
                }
            }
            if family == .systemLarge {
                Divider()
                Text("오늘 일정")
                    .font(.headline)
                agenda(limit: 3)
            }
        }
        .padding(4)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: entry.date)
        return (0..<7).compactMap { offset in
            interval.flatMap { calendar.date(byAdding: .day, value: offset, to: $0.start) }
        }
    }

    private var monthDates: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: entry.date),
              let days = calendar.range(of: .day, in: .month, for: entry.date)
        else { return [] }

        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday + 5) % 7
        return Array(repeating: nil, count: leading)
            + days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map(Optional.some)
    }

    @ViewBuilder
    private func agenda(limit: Int) -> some View {
        if entry.items.isEmpty {
            Text("일정 없음").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(Array(entry.items.prefix(limit)), id: \.self) { item in
                WidgetTask(icon: "calendar", time: item.time, title: item.title)
            }
        }
    }
}

struct MemdoCalendarWidget: Widget {
    let kind = "MemdoCalendarWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CalendarWidgetConfigurationIntent.self,
            provider: CalendarWidgetProvider()
        ) { entry in
            MemdoCalendarWidgetView(entry: entry)
                .containerBackground(
                    MemdoWidgetTheme.background,
                    for: .widget
                )
                .widgetURL(URL(string: "memdo://calendar"))
        }
        .configurationDisplayName("나의 달력")
        .description("일주일 또는 한 달 일정을 한눈에 확인합니다.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct MemdoWidgetBundle: WidgetBundle {
    var body: some Widget {
        MemdoTodayWidget()
        MemdoCalendarWidget()
    }
}

struct MemdoWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MemdoWidgetView(entry: MemdoWidgetEntry(date: .now, items: []))
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
            MemdoWidgetView(entry: MemdoWidgetEntry(date: .now, items: []))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            MemdoCalendarWidgetView(entry: CalendarWidgetEntry(date: .now, range: .week, items: []))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            MemdoCalendarWidgetView(entry: CalendarWidgetEntry(date: .now, range: .month, items: []))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
