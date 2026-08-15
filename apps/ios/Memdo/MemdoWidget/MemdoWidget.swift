import ActivityKit
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
                ? UIColor(red: 1.00, green: 0.78, blue: 0.35, alpha: 1)    // amber (lifted for dark)
                : UIColor(red: 0.996, green: 0.725, blue: 0.149, alpha: 1) // #FEB926 amber
        }
    )

    static func scheduleColor(_ name: String) -> Color? {
        let uiColor: UIColor
        switch name {
        case "coral":
            uiColor = UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 1.00, green: 0.60, blue: 0.55, alpha: 1)
                : UIColor(red: 0.95, green: 0.36, blue: 0.29, alpha: 1) }
        case "amber":
            uiColor = UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 1.00, green: 0.82, blue: 0.45, alpha: 1)
                : UIColor(red: 0.95, green: 0.65, blue: 0.14, alpha: 1) }
        case "sage":
            uiColor = UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.62, green: 0.86, blue: 0.65, alpha: 1)
                : UIColor(red: 0.31, green: 0.67, blue: 0.35, alpha: 1) }
        case "sky":
            uiColor = UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.55, green: 0.80, blue: 1.00, alpha: 1)
                : UIColor(red: 0.19, green: 0.61, blue: 0.92, alpha: 1) }
        case "indigo":
            uiColor = UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.72, green: 0.67, blue: 1.00, alpha: 1)
                : UIColor(red: 0.36, green: 0.30, blue: 0.72, alpha: 1) }
        case "violet":
            uiColor = UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.90, green: 0.65, blue: 1.00, alpha: 1)
                : UIColor(red: 0.64, green: 0.28, blue: 0.84, alpha: 1) }
        default: return nil
        }
        return Color(uiColor: uiColor)
    }
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
                .privacySensitive()
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
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(entry.date.memdoMonth)
                    .font(.caption2)
                Text(entry.date.memdoDay)
                    .font(.title2.bold())
            }
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.date.memdoMonth) \(entry.date.memdoDay)일, 남은 일정 \(entry.today.remainingCount)개")
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
        Text("\(count)개 남음")
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
            if let colorName = item.color, let c = MemdoWidgetTheme.scheduleColor(colorName) {
                Circle()
                    .fill(c)
                    .frame(width: 7, height: 7)
                    .frame(width: 12)
                    .padding(.top, 2)
            } else {
                Image(systemName: item.systemImage)
                    .font(.caption2)
                    .foregroundStyle(item.kind == "task" ? MemdoWidgetTheme.brand : MemdoWidgetTheme.secondary)
                    .frame(width: 12)
            }
            Text(item.time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(MemdoWidgetTheme.secondary)
                .frame(minWidth: 30, alignment: .leading)
            Text(hidesPrivateContent ? "비공개 일정" : item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .privacySensitive()
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
            let visibleItems = Array(day.items.prefix(limit))
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 4) {
                    if let colorName = item.color, let c = MemdoWidgetTheme.scheduleColor(colorName) {
                        Circle()
                            .fill(c)
                            .frame(width: 6, height: 6)
                            .frame(width: 11)
                    } else {
                        Image(systemName: item.systemImage)
                            .font(.caption2)
                            .frame(width: 11)
                    }
                    Text(item.time)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(hidesPrivateContent ? "비공개 일정" : item.title)
                        .lineLimit(1)
                        .privacySensitive()
                    Spacer(minLength: 2)
                    if index == visibleItems.count - 1, day.remainingCount > limit {
                        Text("+\(day.remainingCount - limit)")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
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
                    Link(destination: URL(string: "memdo://schedule/\(item.id.uuidString.lowercased())")!) {
                        WidgetTaskRow(item: item, hidesPrivateContent: hidesPrivateContent)
                    }
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
                .foregroundStyle(isToday ? MemdoWidgetTheme.accent : .primary)
                .frame(width: isLarge ? 23 : 16, height: isLarge ? 23 : 15)
                .background(isToday ? MemdoWidgetTheme.brand : .clear, in: Circle())
            Circle()
                .fill(count > 0 ? MemdoWidgetTheme.brand : .clear)
                .frame(width: 3, height: 3)
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

// MARK: - Live Activity (Workout Tracking)

struct WorkoutTrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutTrackingAttributes.self) { context in
            WorkoutTrackingBannerView(attrs: context.attributes, state: context.state)
        } dynamicIsland: { context in
            let attrs = context.attributes
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: workoutIcon(attrs.activityType))
                        .foregroundStyle(state.isComplete ? .green : MemdoWidgetTheme.brand)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.isComplete {
                        Label("완료", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("운동 중").font(.caption2).foregroundStyle(MemdoWidgetTheme.secondary)
                            Text(timerInterval: attrs.startedAt...Date(timeIntervalSinceNow: 24 * 3600), countsDown: false)
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundStyle(MemdoWidgetTheme.brand)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(workoutLabel(attrs.activityType))
                            .font(.headline)
                            .foregroundStyle(MemdoWidgetTheme.accent)
                        Spacer()
                        if state.isComplete, let endedAt = state.endedAt {
                            let elapsed = Int(endedAt.timeIntervalSince(attrs.startedAt))
                            let h = elapsed / 3600, m = (elapsed % 3600) / 60
                            Text(h > 0 ? "\(h)시간 \(m)분" : "\(m)분")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                        } else {
                            Text(attrs.startedAt.formatted(.dateTime.hour().minute()))
                                .font(.caption)
                                .foregroundStyle(MemdoWidgetTheme.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: workoutIcon(attrs.activityType))
                    .foregroundStyle(state.isComplete ? .green : MemdoWidgetTheme.brand)
                    .font(.caption2.weight(.semibold))
                    .padding(.leading, 4)
            } compactTrailing: {
                if state.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text(timerInterval: attrs.startedAt...Date(timeIntervalSinceNow: 24 * 3600), countsDown: false)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(MemdoWidgetTheme.brand)
                        .frame(maxWidth: 44)
                        .multilineTextAlignment(.trailing)
                }
            } minimal: {
                Image(systemName: state.isComplete ? "checkmark.circle.fill" : workoutIcon(attrs.activityType))
                    .foregroundStyle(state.isComplete ? .green : MemdoWidgetTheme.brand)
                    .font(.caption2)
            }
        }
    }
}

private func workoutIcon(_ type: String) -> String {
    switch type {
    case "running":          "figure.run"
    case "cycling":          "figure.outdoor.cycle"
    case "swimming":         "figure.pool.swim"
    case "strength_training": "dumbbell"
    case "yoga":             "figure.yoga"
    case "hiit":             "figure.highintensity.intervaltraining"
    case "walking":          "figure.walk"
    default:                 "figure.mixed.cardio"
    }
}

private func workoutLabel(_ type: String) -> String {
    switch type {
    case "running":          "러닝"
    case "cycling":          "사이클"
    case "swimming":         "수영"
    case "strength_training": "근력 운동"
    case "yoga":             "요가"
    case "hiit":             "HIIT"
    case "walking":          "걷기"
    default:                 "운동"
    }
}

private struct WorkoutTrackingBannerView: View {
    let attrs: WorkoutTrackingAttributes
    let state: WorkoutTrackingAttributes.TrackingState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workoutIcon(attrs.activityType))
                .foregroundStyle(state.isComplete ? .green : MemdoWidgetTheme.brand)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(workoutLabel(attrs.activityType))
                    .font(.headline)
                    .foregroundStyle(MemdoWidgetTheme.accent)
                if state.isComplete, let endedAt = state.endedAt {
                    let elapsed = Int(endedAt.timeIntervalSince(attrs.startedAt))
                    let h = elapsed / 3600, m = (elapsed % 3600) / 60
                    Text("완료 · " + (h > 0 ? "\(h)시간 \(m)분" : "\(m)분"))
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text(attrs.startedAt.formatted(.dateTime.hour().minute()) + " 시작")
                        .font(.caption)
                        .foregroundStyle(MemdoWidgetTheme.secondary)
                }
            }
            Spacer()
            if !state.isComplete {
                Text(timerInterval: attrs.startedAt...Date(timeIntervalSinceNow: 24 * 3600), countsDown: false)
                    .font(.callout.monospacedDigit().bold())
                    .foregroundStyle(MemdoWidgetTheme.brand)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .padding()
    }
}

// MARK: - Bundle

@main
struct MemdoWidgetBundle: WidgetBundle {
    var body: some Widget {
        MemdoTodayWidget()
        MemdoCalendarWidget()
        WorkoutTrackingLiveActivity()
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
