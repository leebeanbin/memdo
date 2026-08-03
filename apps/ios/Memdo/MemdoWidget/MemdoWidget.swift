import AppIntents
import SwiftUI
import WidgetKit

private enum MemdoWidgetTheme {
    static let background = Color(uiColor: .systemBackground)
    static let accent = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let onAccent = Color(uiColor: .systemBackground)
    static let brand = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.72, green: 0.67, blue: 1, alpha: 1)
                : UIColor(red: 0.36, green: 0.30, blue: 0.72, alpha: 1)
        }
    )
}

private enum MemdoWidgetStorage {
    static let suiteName = "group.com.memdo.ios"
    static let snapshotKey = "today-schedule-snapshot"
    static let hideContentKey = "hide-widget-content"
}

private struct MemdoWidgetSnapshot: Codable {
    let updatedAt: Date
    let days: [MemdoWidgetDay]

    func day(for date: Date) -> MemdoWidgetDay {
        days.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
            ?? MemdoWidgetDay(date: Calendar.current.startOfDay(for: date), completedCount: 0, items: [])
    }

    func nextDay(after date: Date) -> MemdoWidgetDay? {
        days.first {
            $0.date > Calendar.current.startOfDay(for: date) && !$0.items.isEmpty
        }
    }

    static func empty(at date: Date) -> Self {
        Self(updatedAt: date, days: [])
    }

    static func sample(at date: Date) -> Self {
        let calendar = Calendar.current
        func day(_ offset: Int, _ items: [MemdoWidgetItem], completed: Int = 0) -> MemdoWidgetDay {
            MemdoWidgetDay(
                date: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date,
                completedCount: completed,
                items: items
            )
        }
        func item(_ time: String, _ title: String, _ kind: String = "event") -> MemdoWidgetItem {
            MemdoWidgetItem(id: UUID(), time: time, title: title, kind: kind)
        }
        return Self(updatedAt: date, days: [
            day(0, [
                item("10:00", "기획 문서 다듬기"),
                item("14:30", "디자인 시안 확인"),
                item("19:00", "30분 산책", "task"),
                item("저녁", "하루 정리", "task")
            ], completed: 2),
            day(1, [item("09:30", "주간 계획 정리", "task")]),
            day(3, [item("15:00", "프로젝트 미팅")]),
            day(5, [item("오전", "장보기", "task"), item("18:00", "운동", "task")]),
            day(8, [item("11:00", "제품 리뷰")])
        ])
    }
}

private struct MemdoWidgetDay: Codable, Hashable {
    let date: Date
    let completedCount: Int
    let items: [MemdoWidgetItem]

    var remainingCount: Int { items.count }
    var totalCount: Int { completedCount + remainingCount }
}

private struct MemdoWidgetItem: Codable, Hashable {
    let id: UUID
    let time: String
    let title: String
    let kind: String

    var systemImage: String { kind == "task" ? "checkmark.square" : "clock" }
}

private struct MemdoWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MemdoWidgetSnapshot
    let hidesPrivateContent: Bool

    var today: MemdoWidgetDay { snapshot.day(for: date) }
    var nextDay: MemdoWidgetDay? { snapshot.nextDay(after: date) }
}

private func loadWidgetEntry(at date: Date = .now) -> MemdoWidgetEntry {
    let defaults = UserDefaults(suiteName: MemdoWidgetStorage.suiteName)
    let snapshot = defaults
        .flatMap { $0.data(forKey: MemdoWidgetStorage.snapshotKey) }
        .flatMap { try? JSONDecoder().decode(MemdoWidgetSnapshot.self, from: $0) }
        ?? .empty(at: date)
    return MemdoWidgetEntry(
        date: date,
        snapshot: snapshot,
        hidesPrivateContent: defaults?.bool(forKey: MemdoWidgetStorage.hideContentKey) ?? false
    )
}

private func sampleWidgetEntry(at date: Date = .now) -> MemdoWidgetEntry {
    MemdoWidgetEntry(date: date, snapshot: .sample(at: date), hidesPrivateContent: false)
}

private struct MemdoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemdoWidgetEntry {
        sampleWidgetEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (MemdoWidgetEntry) -> Void) {
        completion(context.isPreview ? sampleWidgetEntry() : loadWidgetEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemdoWidgetEntry>) -> Void) {
        let entry = loadWidgetEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private struct MemdoTodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MemdoWidgetEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(inlineText, systemImage: entry.today.items.first?.systemImage ?? "calendar")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var inlineText: String {
        guard let first = entry.today.items.first else {
            return entry.today.completedCount > 0 ? "오늘 일정 완료" : "오늘 일정 없음"
        }
        let title = entry.hidesPrivateContent ? "일정" : first.title
        let remaining = entry.today.remainingCount - 1
        return "\(first.time) \(title)\(remaining > 0 ? " · +\(remaining)" : "")"
    }

    private var circular: some View {
        VStack(spacing: -2) {
            Text(entry.date.memdoMonth)
                .font(.caption2)
            Text(entry.date.memdoDay)
                .font(.title2.bold())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.date.memdoMonth) \(entry.date.memdoDay)일")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("\(entry.date.memdoMonthDay) · \(entry.today.remainingCount)개", systemImage: "calendar")
                .font(.caption.bold())
                .widgetAccentable()
            WidgetCompactAgenda(day: entry.today, limit: 2, hidesPrivateContent: entry.hidesPrivateContent)
        }
        .font(.caption)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.date.memdoMonth)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(MemdoWidgetTheme.secondary)
                    Text(entry.date.memdoDay)
                        .font(.system(.title, design: .rounded, weight: .bold))
                }
                Spacer()
                WidgetCountBadge(count: entry.today.remainingCount)
            }
            WidgetAgenda(
                day: entry.today,
                nextDay: entry.nextDay,
                limit: 2,
                hidesPrivateContent: entry.hidesPrivateContent,
                compact: true
            )
            Spacer(minLength: 0)
        }
        .padding(2)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            WidgetWeekIndex(entry: entry)
                .frame(width: 145)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("오늘 일정")
                        .font(.headline)
                    Spacer()
                    WidgetCountBadge(count: entry.today.remainingCount)
                }
                WidgetAgenda(
                    day: entry.today,
                    nextDay: entry.nextDay,
                    limit: 3,
                    hidesPrivateContent: entry.hidesPrivateContent
                )
            }
        }
        .padding(2)
    }
}

private struct WidgetCountBadge: View {
    let count: Int

    var body: some View {
        Label("\(count)개", systemImage: "calendar")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(MemdoWidgetTheme.secondary)
            .fixedSize()
    }
}

private struct WidgetTaskRow: View {
    let item: MemdoWidgetItem
    let hidesPrivateContent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: item.systemImage)
                .font(.caption2)
                .foregroundStyle(item.kind == "task" ? MemdoWidgetTheme.brand : MemdoWidgetTheme.secondary)
                .frame(width: 12)
            Text(item.time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(MemdoWidgetTheme.secondary)
                .frame(minWidth: 30, alignment: .leading)
            Text(hidesPrivateContent ? "비공개 일정" : item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetCompactAgenda: View {
    let day: MemdoWidgetDay
    let limit: Int
    let hidesPrivateContent: Bool

    var body: some View {
        if day.items.isEmpty {
            Text(day.completedCount > 0 ? "오늘 일정 완료" : "일정 없음")
                .foregroundStyle(.secondary)
        } else {
            ForEach(day.items.prefix(limit), id: \.id) { item in
                Text("\(item.time)  \(hidesPrivateContent ? "비공개 일정" : item.title)")
                    .lineLimit(1)
            }
            if day.remainingCount > limit {
                Text("+\(day.remainingCount - limit)개 더")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WidgetAgenda: View {
    let day: MemdoWidgetDay
    let nextDay: MemdoWidgetDay?
    let limit: Int
    let hidesPrivateContent: Bool
    var compact = false

    var body: some View {
        if day.items.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: compact ? 6 : 7) {
                ForEach(day.items.prefix(limit), id: \.id) { item in
                    WidgetTaskRow(item: item, hidesPrivateContent: hidesPrivateContent)
                }
                if day.remainingCount > limit {
                    Text("+\(day.remainingCount - limit)개 더")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MemdoWidgetTheme.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                day.completedCount > 0 ? "오늘 일정 완료" : "오늘은 어떤 하루를 보낼까요?",
                systemImage: day.completedCount > 0 ? "checkmark.circle.fill" : "sparkles"
            )
            .font(.caption.weight(.semibold))
            if let nextDay, let next = nextDay.items.first {
                Text("다음 · \(nextDay.date.memdoMonthDay) \(next.time)")
                    .font(.caption2)
                    .foregroundStyle(MemdoWidgetTheme.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct WidgetWeekIndex: View {
    let entry: MemdoWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.date.memdoMonth)
                .font(.headline)
            HStack(spacing: 2) {
                ForEach(entry.date.memdoWeekDates, id: \.self) { date in
                    WidgetWeekDay(
                        date: date,
                        count: entry.snapshot.day(for: date).remainingCount,
                        isToday: Calendar.current.isDateInToday(date)
                    )
                }
            }
            Text(entry.today.remainingCount > 0 ? "남은 일정 \(entry.today.remainingCount)개" : "오늘 일정 정리됨")
                .font(.caption2)
                .foregroundStyle(MemdoWidgetTheme.secondary)
        }
    }
}

private struct WidgetWeekDay: View {
    let date: Date
    let count: Int
    let isToday: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(date.memdoWeekday)
                .font(.caption2)
            Text(date.memdoDay)
                .font(.caption.weight(.semibold))
            Circle()
                .fill(count > 0 ? MemdoWidgetTheme.brand : .clear)
                .frame(width: 3, height: 3)
        }
        .foregroundStyle(isToday ? MemdoWidgetTheme.onAccent : .primary)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(isToday ? MemdoWidgetTheme.accent : .clear, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.memdoMonthDay), 일정 \(count)개")
    }
}

struct MemdoTodayWidget: Widget {
    let kind = "MemdoTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemdoWidgetProvider()) { entry in
            MemdoTodayWidgetView(entry: entry)
                .containerBackground(MemdoWidgetTheme.background, for: .widget)
                .widgetURL(URL(string: "memdo://today"))
        }
        .configurationDisplayName("오늘의 Memdo")
        .description("잠금화면과 홈 화면에서 오늘의 일정과 남은 개수를 확인합니다.")
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

    @Parameter(title: "보기", default: .month)
    var range: CalendarWidgetRange
}

private struct CalendarWidgetEntry: TimelineEntry {
    let date: Date
    let range: CalendarWidgetRange
    let snapshot: MemdoWidgetSnapshot
    let hidesPrivateContent: Bool

    var today: MemdoWidgetDay { snapshot.day(for: date) }
}

private struct CalendarWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CalendarWidgetEntry {
        let entry = sampleWidgetEntry()
        return CalendarWidgetEntry(
            date: entry.date,
            range: .month,
            snapshot: entry.snapshot,
            hidesPrivateContent: false
        )
    }

    func snapshot(for configuration: CalendarWidgetConfigurationIntent, in context: Context) async -> CalendarWidgetEntry {
        calendarEntry(for: configuration, preview: context.isPreview)
    }

    func timeline(for configuration: CalendarWidgetConfigurationIntent, in context: Context) async -> Timeline<CalendarWidgetEntry> {
        let entry = calendarEntry(for: configuration, preview: false)
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        return Timeline(entries: [entry], policy: .after(nextDay))
    }

    private func calendarEntry(
        for configuration: CalendarWidgetConfigurationIntent,
        preview: Bool
    ) -> CalendarWidgetEntry {
        let entry = preview ? sampleWidgetEntry() : loadWidgetEntry()
        return CalendarWidgetEntry(
            date: entry.date,
            range: configuration.range,
            snapshot: entry.snapshot,
            hidesPrivateContent: entry.hidesPrivateContent
        )
    }
}

private struct MemdoCalendarWidgetView: View {
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
        VStack(alignment: .leading, spacing: 10) {
            calendarHeader
            HStack(spacing: 5) {
                ForEach(entry.date.memdoWeekDates, id: \.self) { date in
                    Link(destination: date.memdoCalendarURL) {
                        WidgetWeekDay(
                            date: date,
                            count: entry.snapshot.day(for: date).remainingCount,
                            isToday: Calendar.current.isDateInToday(date)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            if family == .systemLarge {
                largeWeekAgenda
            } else {
                WidgetAgenda(
                    day: entry.today,
                    nextDay: entry.snapshot.nextDay(after: entry.date),
                    limit: 3,
                    hidesPrivateContent: entry.hidesPrivateContent
                )
            }
        }
        .padding(2)
    }

    private var largeWeekAgenda: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("오늘")
                    .font(.headline)
                WidgetAgenda(
                    day: entry.today,
                    nextDay: entry.snapshot.nextDay(after: entry.date),
                    limit: 4,
                    hidesPrivateContent: entry.hidesPrivateContent
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("다가오는 일정")
                    .font(.headline)
                if let nextDay = entry.snapshot.nextDay(after: entry.date) {
                    Text(nextDay.date.memdoMonthDay)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MemdoWidgetTheme.secondary)
                    WidgetAgenda(
                        day: nextDay,
                        nextDay: nil,
                        limit: 4,
                        hidesPrivateContent: entry.hidesPrivateContent
                    )
                } else {
                    Text("예정된 일정이 없어요")
                        .font(.caption)
                        .foregroundStyle(MemdoWidgetTheme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var month: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 4) {
            calendarHeader
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7),
                spacing: family == .systemLarge ? 6 : 1
            ) {
                ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MemdoWidgetTheme.secondary)
                }
                ForEach(entry.date.memdoMonthDates.indices, id: \.self) { index in
                    if let date = entry.date.memdoMonthDates[index] {
                        Link(destination: date.memdoCalendarURL) {
                            WidgetMonthDay(
                                date: date,
                                count: entry.snapshot.day(for: date).remainingCount,
                                isToday: Calendar.current.isDateInToday(date),
                                isLarge: family == .systemLarge
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: family == .systemLarge ? 29 : 17)
                    }
                }
            }
            if family == .systemLarge {
                Divider()
                HStack {
                    Text("오늘 일정")
                        .font(.headline)
                    Spacer()
                    WidgetCountBadge(count: entry.today.remainingCount)
                }
                WidgetAgenda(
                    day: entry.today,
                    nextDay: entry.snapshot.nextDay(after: entry.date),
                    limit: 3,
                    hidesPrivateContent: entry.hidesPrivateContent
                )
            }
        }
        .padding(2)
    }

    private var calendarHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.date.memdoYearMonth)
                .font(.headline)
            Spacer()
            Label("\(monthRemainingCount)개 일정", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoWidgetTheme.secondary)
        }
    }

    private var monthRemainingCount: Int {
        entry.snapshot.days
            .filter { Calendar.current.isDate($0.date, equalTo: entry.date, toGranularity: .month) }
            .reduce(0) { $0 + $1.remainingCount }
    }
}

private struct WidgetMonthDay: View {
    let date: Date
    let count: Int
    let isToday: Bool
    let isLarge: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(date.memdoDay)
                .font(.caption2.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? MemdoWidgetTheme.onAccent : .primary)
                .frame(width: isLarge ? 23 : 16, height: isLarge ? 23 : 15)
                .background(isToday ? MemdoWidgetTheme.brand : .clear, in: Circle())
            if isLarge {
                Text(count > 0 ? "\(count)" : "")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(MemdoWidgetTheme.secondary)
                    .frame(height: 7)
            } else {
                Circle()
                    .fill(count > 0 ? MemdoWidgetTheme.brand : .clear)
                    .frame(width: 2.5, height: 2.5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isLarge ? 31 : 17)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.memdoMonthDay), 일정 \(count)개")
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
                .containerBackground(MemdoWidgetTheme.background, for: .widget)
                .widgetURL(URL(string: "memdo://calendar"))
        }
        .configurationDisplayName("나의 달력")
        .description("일주일 또는 한 달의 일정 밀도와 오늘 일정을 확인합니다.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private extension Date {
    var memdoMonth: String { "\(Calendar.current.component(.month, from: self))월" }
    var memdoDay: String { "\(Calendar.current.component(.day, from: self))" }
    var memdoMonthDay: String { "\(memdoMonth) \(memdoDay)일" }
    var memdoYearMonth: String {
        let calendar = Calendar.current
        return "\(calendar.component(.year, from: self))년 \(calendar.component(.month, from: self))월"
    }
    var memdoWeekday: String {
        ["일", "월", "화", "수", "목", "금", "토"][Calendar.current.component(.weekday, from: self) - 1]
    }
    var memdoWeekDates: [Date] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: self)
        let mondayOffset = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -mondayOffset, to: calendar.startOfDay(for: self)) ?? self
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var memdoMonthDates: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: self),
              let days = calendar.range(of: .day, in: .month, for: self)
        else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday + 5) % 7
        return Array(repeating: nil, count: leading)
            + days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map(Optional.some)
    }
    var memdoCalendarURL: URL {
        var components = URLComponents()
        components.scheme = "memdo"
        components.host = "calendar"
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day], from: self)
        components.queryItems = [
            URLQueryItem(
                name: "date",
                value: String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            )
        ]
        return components.url ?? URL(string: "memdo://calendar")!
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
        let today = sampleWidgetEntry()
        Group {
            MemdoTodayWidgetView(entry: today)
                .previewContext(WidgetPreviewContext(family: .accessoryInline))
                .previewDisplayName("잠금화면 · 인라인")
            MemdoTodayWidgetView(entry: today)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("잠금화면 · 원형")
            MemdoTodayWidgetView(entry: today)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("잠금화면 · 직사각형")
            MemdoTodayWidgetView(entry: today)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("오늘 · Small")
            MemdoTodayWidgetView(entry: today)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("오늘 · Medium")
            MemdoTodayWidgetView(entry: MemdoWidgetEntry(
                date: today.date,
                snapshot: .empty(at: today.date),
                hidesPrivateContent: false
            ))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("오늘 · 빈 상태")
            MemdoTodayWidgetView(entry: today)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .preferredColorScheme(.dark)
                .previewDisplayName("오늘 · Dark")
            MemdoCalendarWidgetView(entry: calendarPreview(range: .week, entry: today))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("주간 · Medium")
            MemdoCalendarWidgetView(entry: calendarPreview(range: .week, entry: today))
                .previewContext(WidgetPreviewContext(family: .systemLarge))
                .previewDisplayName("주간 · Large")
            MemdoCalendarWidgetView(entry: calendarPreview(range: .month, entry: today))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("월간 · Medium")
            MemdoCalendarWidgetView(entry: calendarPreview(range: .month, entry: today))
                .previewContext(WidgetPreviewContext(family: .systemLarge))
                .previewDisplayName("월간 · Large")
        }
    }

    private static func calendarPreview(
        range: CalendarWidgetRange,
        entry: MemdoWidgetEntry
    ) -> CalendarWidgetEntry {
        CalendarWidgetEntry(
            date: entry.date,
            range: range,
            snapshot: entry.snapshot,
            hidesPrivateContent: false
        )
    }
}
