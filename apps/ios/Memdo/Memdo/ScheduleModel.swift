import Foundation
import Observation
import Supabase
import WidgetKit

enum ScheduleKind: String, CaseIterable, Identifiable {
    case event
    case task

    var id: String { rawValue }

    var label: String {
        switch self {
        case .event: "시간 일정"
        case .task: "할 일"
        }
    }
}

struct ScheduleCalendar: Identifiable, Equatable, Hashable {
    enum Provider: String {
        case memdo
        case google

        var displayName: String {
            switch self {
            case .memdo: "내 일정"
            case .google: "Google Calendar"
            }
        }

        var systemImage: String {
            switch self {
            case .memdo: "calendar"
            case .google: "calendar.badge.checkmark"
            }
        }
    }

    let id: String
    let title: String
    let purpose: String
    let provider: Provider

    static let unassigned = ScheduleCalendar(id: "", title: "캘린더 선택", purpose: "", provider: .memdo)
}

enum ScheduleRepeatRule: String, CaseIterable, Identifiable {
    case never
    case daily
    case weekdays
    case weekly
    case biweekly
    case monthly
    case yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: "반복 안 함"
        case .daily: "매일"
        case .weekdays: "평일마다"
        case .weekly: "매주"
        case .biweekly: "2주마다"
        case .monthly: "매월"
        case .yearly: "매년"
        }
    }
}

enum ScheduleStatus: String {
    case planned
    case inProgress = "in_progress"
    case partial
    case completed
    case skipped
    case rescheduled
    case cancelled
}

enum ScheduleTimeBucket: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case anytime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: "오전"
        case .afternoon: "오후"
        case .evening: "저녁"
        case .anytime: "언제든"
        }
    }

    static func inferred(from date: Date) -> Self {
        switch Calendar.current.component(.hour, from: date) {
        case 0..<12: .morning
        case 12..<18: .afternoon
        default: .evening
        }
    }
}

struct ScheduleReminderOption: Identifiable, Hashable {
    let offsetMinutes: Int?
    let label: String

    var id: Int { offsetMinutes ?? -1 }

    static let options = [
        ScheduleReminderOption(offsetMinutes: nil, label: "알림 없음"),
        ScheduleReminderOption(offsetMinutes: 0, label: "시간에 맞춰"),
        ScheduleReminderOption(offsetMinutes: 5, label: "5분 전"),
        ScheduleReminderOption(offsetMinutes: 10, label: "10분 전"),
        ScheduleReminderOption(offsetMinutes: 30, label: "30분 전"),
        ScheduleReminderOption(offsetMinutes: 60, label: "1시간 전"),
        ScheduleReminderOption(offsetMinutes: 1_440, label: "1일 전")
    ]

    static func label(for offsetMinutes: Int?) -> String {
        options.first { $0.offsetMinutes == offsetMinutes }?.label
            ?? offsetMinutes.map { "\($0)분 전" }
            ?? "알림 없음"
    }
}

struct ScheduleLocation: Equatable {
    enum Provider: String {
        case appleMaps = "apple_maps"
        case googlePlaces = "google_places"
        case manual
    }

    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var provider: Provider?
    var providerID: String?

    init(
        name: String,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        provider: Provider? = nil,
        providerID: String? = nil
    ) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.provider = provider
        self.providerID = providerID
    }

    var displayText: String {
        guard let address, !address.isEmpty, address != name else { return name }
        return "\(name) · \(address)"
    }
}

struct ScheduleDetail: Identifiable, Equatable {
    let id: UUID
    var scheduledDate: Date
    var startAt: Date?
    var endAt: Date?
    var dueAt: Date?
    var title: String
    var status: ScheduleStatus
    var locationValue: ScheduleLocation?
    var memo: String
    var reminderOffsetMinutes: Int?
    var repeatRule: ScheduleRepeatRule
    var kind: ScheduleKind
    var calendar: ScheduleCalendar
    var isAllDay: Bool
    var timeBucket: ScheduleTimeBucket
    var sortOrder: Int
    var version: Int

    init(
        id: UUID = UUID(),
        scheduledDate: Date,
        startAt: Date? = nil,
        endAt: Date? = nil,
        dueAt: Date? = nil,
        title: String,
        status: ScheduleStatus = .planned,
        locationValue: ScheduleLocation? = nil,
        memo: String = "",
        reminderOffsetMinutes: Int? = 30,
        repeatRule: ScheduleRepeatRule = .never,
        kind: ScheduleKind = .event,
        calendar: ScheduleCalendar,
        isAllDay: Bool = false,
        timeBucket: ScheduleTimeBucket = .anytime,
        sortOrder: Int = 0,
        version: Int = 1
    ) {
        self.id = id
        self.scheduledDate = Calendar.current.startOfDay(for: scheduledDate)
        self.startAt = startAt
        self.endAt = endAt
        self.dueAt = dueAt
        self.title = title
        self.status = status
        self.locationValue = locationValue
        self.memo = memo
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.repeatRule = repeatRule
        self.kind = kind
        self.calendar = calendar
        self.isAllDay = isAllDay
        self.timeBucket = startAt.map { ScheduleTimeBucket.inferred(from: $0) } ?? timeBucket
        self.sortOrder = sortOrder
        self.version = version
    }

    var source: String { calendar.provider.displayName }
    var isExternal: Bool { calendar.provider == .google }
    var isDone: Bool {
        get { status == .completed }
        set { status = newValue ? .completed : .planned }
    }
    var location: String {
        get { locationValue?.displayText ?? "" }
        set {
            locationValue = newValue.isEmpty
                ? nil
                : ScheduleLocation(name: newValue, provider: .manual)
        }
    }
    var reminder: String { ScheduleReminderOption.label(for: reminderOffsetMinutes) }
    var day: Int { Calendar.current.component(.day, from: scheduledDate) }
    var time: String { startAt.map(Self.clockText) ?? "" }
    var hasScheduledTime: Bool { startAt != nil && endAt != nil }
    var displayTime: String {
        guard !isAllDay else { return "종일" }
        guard let startAt, let endAt else { return timeBucket.label }
        return "\(Self.clockText(startAt))–\(Self.clockText(endAt))"
    }
    var startTimeText: String { startAt.map(Self.clockText) ?? timeBucket.label }
    var endTimeText: String { endAt.map(Self.clockText) ?? "" }
    var dueTimeText: String? { dueAt.map(Self.clockText) }
    var dateText: String {
        let components = Calendar.current.dateComponents([.month, .day], from: scheduledDate)
        return "\(components.month ?? 0)월 \(components.day ?? 0)일"
    }
    var timeSortKey: Date { isAllDay ? scheduledDate : startAt ?? scheduledDate.endOfDay }
    var kindLabel: String { kind.label }
    var isTimeRangeValid: Bool {
        switch (startAt, endAt) {
        case let (startAt?, endAt?): endAt > startAt
        case (nil, nil): kind == .task
        default: false
        }
    }

    private static func clockText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

}

enum ScheduleStoreState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
@Observable
final class ScheduleStore {
    private(set) var schedules: [ScheduleDetail] = []
    private(set) var calendars: [ScheduleCalendar] = []
    private(set) var state = ScheduleStoreState.idle
    private let repository: ScheduleRepository

    init(repository: ScheduleRepository) {
        self.repository = repository
    }

    #if DEBUG
    static func preview() -> ScheduleStore {
        let configuration = MemdoConfiguration(
            projectURL: URL(string: "http://127.0.0.1:54321")!,
            publishableKey: "sb_publishable_preview"
        )
        let client = SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey
        )
        return ScheduleStore(
            repository: ScheduleRepository(configuration: configuration, auth: client)
        )
    }
    #endif

    func items(for date: Date) -> [ScheduleDetail] {
        schedules
            .filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) }
            .sorted { $0.timeSortKey < $1.timeSortKey }
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            let snapshot = try await repository.load(around: .now)
            schedules = snapshot.schedules
            calendars = snapshot.calendars
            state = .loaded
            updateWidgetSnapshot()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func save(_ schedule: ScheduleDetail) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            let previous = schedules[index]
            schedules[index] = schedule
            updateWidgetSnapshot()
            Task { await update(schedule, replacing: previous) }
        } else {
            schedules.append(schedule)
            updateWidgetSnapshot()
            Task { await create(schedule) }
        }
    }

    private func create(_ schedule: ScheduleDetail) async {
        do {
            let saved = try await repository.create(schedule)
            if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
                schedules[index] = saved
                updateWidgetSnapshot()
            }
        } catch {
            schedules.removeAll { $0.id == schedule.id }
            updateWidgetSnapshot()
            state = .failed(error.localizedDescription)
        }
    }

    private func update(_ schedule: ScheduleDetail, replacing previous: ScheduleDetail) async {
        do {
            replace(schedule.id, with: try await repository.update(schedule))
        } catch {
            replace(schedule.id, with: previous)
            state = .failed(error.localizedDescription)
        }
        updateWidgetSnapshot()
    }

    func reset() {
        schedules = []
        calendars = []
        state = .idle
        updateWidgetSnapshot()
    }

    private func replace(_ id: UUID, with schedule: ScheduleDetail) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index] = schedule
    }

    func toggleDone(id: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == id }),
              schedules[index].kind == .task else { return }
        var schedule = schedules[index]
        schedule.isDone.toggle()
        save(schedule)
    }

    func move(id: UUID, to date: Date) {
        guard let schedule = schedules.first(where: { $0.id == id }) else { return }
        var moved = schedule
        let calendar = Calendar.current
        let oldDate = moved.scheduledDate
        moved.scheduledDate = calendar.startOfDay(for: date)

        if let oldStart = moved.startAt, let oldEnd = moved.endAt {
            let duration = oldEnd.timeIntervalSince(oldStart)
            let time = calendar.dateComponents([.hour, .minute, .second], from: oldStart)
            guard let newStart = calendar.date(
                bySettingHour: time.hour ?? 0,
                minute: time.minute ?? 0,
                second: time.second ?? 0,
                of: date
            ) else { return }
            moved.startAt = newStart
            moved.endAt = newStart.addingTimeInterval(duration)
        }

        if let dueAt = moved.dueAt, calendar.isDate(dueAt, inSameDayAs: oldDate) {
            let dueTime = calendar.dateComponents([.hour, .minute, .second], from: dueAt)
            moved.dueAt = calendar.date(
                bySettingHour: dueTime.hour ?? 0,
                minute: dueTime.minute ?? 0,
                second: dueTime.second ?? 0,
                of: date
            )
        }
        assert(calendar.isDate(moved.scheduledDate, inSameDayAs: date))
        save(moved)
    }

    func delete(id: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        let schedule = schedules.remove(at: index)
        updateWidgetSnapshot()
        Task { await delete(schedule, originalIndex: index) }
    }

    private func delete(_ schedule: ScheduleDetail, originalIndex: Int) async {
        do {
            try await repository.delete(schedule)
        } catch {
            schedules.insert(schedule, at: min(originalIndex, schedules.count))
            updateWidgetSnapshot()
            state = .failed(error.localizedDescription)
        }
    }

    private func updateWidgetSnapshot() {
        let calendar = Calendar.current
        let now = Date.now
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .month, value: 2, to: start) ?? now
        let visibleSchedules = schedules.filter { $0.scheduledDate >= start && $0.scheduledDate < end }
        let grouped = Dictionary(grouping: visibleSchedules) { calendar.startOfDay(for: $0.scheduledDate) }
        let days = grouped.keys.sorted().map { date in
            let schedules = (grouped[date] ?? []).sorted { $0.timeSortKey < $1.timeSortKey }
            let active = schedules.filter(\.isWidgetActive)
            return WidgetScheduleDay(
                date: date,
                completedCount: schedules.filter(\.isDone).count,
                items: active.map {
                    WidgetScheduleItem(
                        id: $0.id,
                        time: $0.startTimeText,
                        title: $0.title,
                        kind: $0.kind.rawValue
                    )
                }
            )
        }
        let snapshot = WidgetScheduleSnapshot(updatedAt: now, days: days)
        assert(days == days.sorted { $0.date < $1.date })
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: "group.com.memdo.ios")?.set(data, forKey: "today-schedule-snapshot")
        WidgetCenter.shared.reloadAllTimelines()
    }

}

private struct WidgetScheduleSnapshot: Codable {
    let updatedAt: Date
    let days: [WidgetScheduleDay]
}

private struct WidgetScheduleDay: Codable, Equatable {
    let date: Date
    let completedCount: Int
    let items: [WidgetScheduleItem]
}

private struct WidgetScheduleItem: Codable, Equatable {
    let id: UUID
    let time: String
    let title: String
    let kind: String
}

private extension ScheduleDetail {
    var isWidgetActive: Bool {
        !isDone && status != .cancelled && status != .skipped && status != .rescheduled
    }
}

private extension Date {
    var endOfDay: Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: self) ?? self
    }
}
