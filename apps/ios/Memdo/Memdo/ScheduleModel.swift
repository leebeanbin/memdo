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

enum MeetingProvider: String {
    case zoom
    case meet
    case teams

    var label: String {
        switch self {
        case .zoom: "Zoom"
        case .meet: "Google Meet"
        case .teams: "Teams"
        }
    }

    var systemImage: String { "video.fill" }

    /// Recognises only known video-meeting hosts so a plain link in a note
    /// doesn't get mistaken for a joinable meeting (generic links = Phase 4).
    static func recognized(_ url: URL) -> MeetingProvider? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("zoom.us") { return .zoom }
        if host.contains("meet.google.com") { return .meet }
        if host.contains("teams.microsoft.com") || host.contains("teams.live.com") { return .teams }
        return nil
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
        // Trust the caller's bucket (matching the server-backed init). Whoever sets a
        // start time is responsible for deriving the bucket via `.inferred(from:)`.
        self.timeBucket = timeBucket
        self.sortOrder = sortOrder
        self.version = version
    }

    var source: String { calendar.provider.displayName }
    var isExternal: Bool { calendar.provider == .google }
    // Rescheduled/cancelled/skipped entries are kept for history but hidden from
    // the active lists so a moved item doesn't leave a ghost on its old day.
    var isActive: Bool { status != .rescheduled && status != .cancelled && status != .skipped }
    var isReschedulable: Bool { status == .planned || status == .inProgress || status == .partial }
    /// First recognised video-meeting link found in the note or location.
    var meetingURL: URL? {
        let text = [memo, location].filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, MeetingProvider.recognized(url) != nil {
                return url
            }
        }
        return nil
    }
    var meetingProvider: MeetingProvider? { meetingURL.flatMap(MeetingProvider.recognized) }
    /// Non-meeting web links found in the note/location, surfaced as attachments.
    var attachedLinks: [URL] {
        let text = [memo, location].filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let meeting = meetingURL
        var seen = Set<String>()
        var links: [URL] = []
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, url.scheme == "http" || url.scheme == "https", url != meeting else { continue }
            if seen.insert(url.absoluteString).inserted { links.append(url) }
        }
        return links
    }
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
    /// Failure from a single item's create/update/delete/reschedule -- surfaced as a
    /// dismissible, non-blocking notice. `state` is reserved for load() failures,
    /// which take down the whole collection; a single item failing shouldn't.
    private(set) var lastWriteError: String?
    private let repository: ScheduleRepository
    private var lastWidgetDays: [MemdoWidgetDay]?
    private var lastSyncCursor: String?
    /// IDs with a create/update/delete/reschedule in flight. Re-entrant calls for the
    /// same id (e.g. a double-tapped completion toggle) are dropped rather than firing
    /// a second request that's guaranteed to lose the optimistic-lock race.
    private var pendingWriteIDs: Set<UUID> = []
    private var loadedFrom: Date?
    private var loadedTo: Date?
    private(set) var isLoadingRange = false

    func isPending(_ id: UUID) -> Bool {
        pendingWriteIDs.contains(id)
    }

    func dismissWriteError() {
        lastWriteError = nil
    }

    init(repository: ScheduleRepository) {
        self.repository = repository
    }

    #if DEBUG
    static func preview() -> ScheduleStore {
        // Previews never call load(), so the repository is inert (no network is
        // performed). Sample data is seeded directly so previews render content.
        let configuration = MemdoConfiguration(
            projectURL: URL(string: "http://127.0.0.1:54321")!,
            publishableKey: "sb_publishable_preview"
        )
        let client = SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey
        )
        let store = ScheduleStore(
            repository: ScheduleRepository(configuration: configuration, auth: client)
        )
        let calendar = ScheduleCalendar(
            id: "00000000-0000-4000-8000-000000000001",
            title: "개인",
            purpose: "personal",
            provider: .memdo
        )
        let today = Calendar.current.startOfDay(for: .now)
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today
        store.calendars = [calendar]
        store.schedules = [
            ScheduleDetail(
                scheduledDate: today,
                startAt: start,
                endAt: start.addingTimeInterval(3_600),
                title: "기획 문서 다듬기",
                kind: .event,
                calendar: calendar
            ),
            ScheduleDetail(scheduledDate: today, title: "30분 산책", kind: .task, calendar: calendar)
        ]
        store.state = .loaded
        return store
    }
    #endif

    /// Throws on failure rather than returning an empty array, so the caller can
    /// tell "no matches" apart from "the request failed" instead of showing the
    /// same empty state for both.
    func search(_ query: String) async throws -> [ScheduleDetail] {
        let calendarsByID = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0) })
        let dtos = try await repository.search(query: query)
        return dtos.compactMap { dto in
            guard let calendar = calendarsByID[dto.calendarId] else { return nil }
            return try? ScheduleDetail(dto: dto, calendar: calendar)
        }
    }

    func items(for date: Date) -> [ScheduleDetail] {
        schedules
            .filter { $0.isActive && Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) }
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
            let calendar = Calendar.current
            loadedFrom = calendar.date(byAdding: .day, value: -30, to: .now)
            loadedTo = calendar.date(byAdding: .day, value: 60, to: .now)
            updateWidgetSnapshot()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Extends the loaded window to cover `date` when the user has navigated
    /// outside what load() originally fetched (-30/+60 days around launch time),
    /// merging the results in rather than replacing the store's schedules. Without
    /// this, browsing far enough shows an empty day that was never actually
    /// fetched, indistinguishable from a genuinely empty one.
    func ensureLoaded(for date: Date) async {
        guard state == .loaded, let loadedFrom, let loadedTo, !isLoadingRange else { return }
        let calendar = Calendar.current
        let padding = 30

        if date < loadedFrom {
            let newFrom = calendar.date(byAdding: .day, value: -padding, to: date) ?? date
            await fetchRange(from: newFrom, to: loadedFrom)
            self.loadedFrom = newFrom
        } else if date > loadedTo {
            let newTo = calendar.date(byAdding: .day, value: padding, to: date) ?? date
            await fetchRange(from: loadedTo, to: newTo)
            self.loadedTo = newTo
        }
    }

    private func fetchRange(from: Date, to: Date) async {
        isLoadingRange = true
        defer { isLoadingRange = false }
        do {
            let fetched = try await repository.loadRange(from: from, to: to)
            merge(fetched)
        } catch {
            lastWriteError = error.localizedDescription
        }
    }

    private func merge(_ fetched: [ScheduleDetail]) {
        for item in fetched {
            if let index = schedules.firstIndex(where: { $0.id == item.id }) {
                schedules[index] = item
            } else {
                schedules.append(item)
            }
        }
        updateWidgetSnapshot()
    }

    /// Best-effort incremental pull of changes made elsewhere (other devices or
    /// external edits) since the last sync cursor. Layered on top of `load()`.
    func refresh() async {
        guard state == .loaded else { return }
        let calendarsByID = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0) })
        var cursor = lastSyncCursor
        var changed = false
        do {
            var hasMore = true
            while hasMore {
                let page = try await repository.sync(cursor: cursor)
                for item in page.items {
                    if item.operation == "delete" {
                        if let id = UUID(uuidString: item.id), schedules.contains(where: { $0.id == id }) {
                            schedules.removeAll { $0.id == id }
                            changed = true
                        }
                    } else if let dto = item.data,
                              let calendar = calendarsByID[dto.calendarId],
                              let mapped = try? ScheduleDetail(dto: dto, calendar: calendar) {
                        if let index = schedules.firstIndex(where: { $0.id == mapped.id }) {
                            schedules[index] = mapped
                        } else {
                            schedules.append(mapped)
                        }
                        changed = true
                    }
                }
                cursor = page.nextCursor ?? cursor
                hasMore = page.hasMore
            }
            lastSyncCursor = cursor
            if changed { updateWidgetSnapshot() }
        } catch {
            // Refresh is best-effort; leave current data intact on failure.
        }
    }

    /// Creates a recurrence rule on the backend, which materialises the
    /// occurrences server-side, then reloads to pull them in.
    func createRecurring(_ schedule: ScheduleDetail) async {
        do {
            try await repository.createRule(schedule)
            await load()
        } catch {
            lastWriteError = error.localizedDescription
        }
    }

    func save(_ schedule: ScheduleDetail) {
        guard !pendingWriteIDs.contains(schedule.id) else { return }
        pendingWriteIDs.insert(schedule.id)
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            let previous = schedules[index]
            schedules[index] = schedule
            updateWidgetSnapshot()
            Task {
                await update(schedule, replacing: previous)
                pendingWriteIDs.remove(schedule.id)
            }
        } else {
            schedules.append(schedule)
            updateWidgetSnapshot()
            Task {
                await create(schedule)
                pendingWriteIDs.remove(schedule.id)
            }
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
            lastWriteError = error.localizedDescription
        }
    }

    private func update(_ schedule: ScheduleDetail, replacing previous: ScheduleDetail) async {
        do {
            replace(schedule.id, with: try await repository.update(schedule))
        } catch {
            replace(schedule.id, with: previous)
            lastWriteError = error.localizedDescription
        }
        updateWidgetSnapshot()
    }

    func reset() {
        schedules = []
        calendars = []
        state = .idle
        lastSyncCursor = nil
        loadedFrom = nil
        loadedTo = nil
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
        guard !pendingWriteIDs.contains(id) else { return }
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        let original = schedules[index]
        var moved = original
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

        // The backend only reschedules live entries (preserving the original as
        // history); completed/cancelled ones fall back to a plain in-place update.
        guard original.isReschedulable else {
            save(moved)
            return
        }
        schedules[index] = moved
        updateWidgetSnapshot()
        pendingWriteIDs.insert(id)
        Task {
            await reschedule(original: original, moved: moved)
            pendingWriteIDs.remove(id)
        }
    }

    private func reschedule(original: ScheduleDetail, moved: ScheduleDetail) async {
        do {
            let result = try await repository.reschedule(moved, baseVersion: original.version)
            schedules.removeAll { $0.id == original.id }
            schedules.append(result.original)
            schedules.append(result.replacement)
            updateWidgetSnapshot()
        } catch {
            if let index = schedules.firstIndex(where: { $0.id == original.id }) {
                schedules[index] = original
            }
            updateWidgetSnapshot()
            lastWriteError = error.localizedDescription
        }
    }

    func delete(id: UUID) {
        guard !pendingWriteIDs.contains(id) else { return }
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        let schedule = schedules.remove(at: index)
        updateWidgetSnapshot()
        pendingWriteIDs.insert(id)
        Task {
            await delete(schedule)
            pendingWriteIDs.remove(id)
        }
    }

    private func delete(_ schedule: ScheduleDetail) async {
        do {
            try await repository.delete(schedule)
        } catch {
            // Restore by identity, not a stale index — other optimistic edits may
            // have shifted positions. Lists re-sort by timeSortKey on read.
            if !schedules.contains(where: { $0.id == schedule.id }) {
                schedules.append(schedule)
            }
            updateWidgetSnapshot()
            lastWriteError = error.localizedDescription
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
            return MemdoWidgetDay(
                date: date,
                completedCount: schedules.filter(\.isDone).count,
                items: active.map {
                    MemdoWidgetItem(
                        id: $0.id,
                        time: $0.startTimeText,
                        title: $0.title,
                        kind: $0.kind.rawValue
                    )
                }
            )
        }
        // Optimistic updates call this twice per edit (local apply + server confirm).
        // Only rewrite storage and reload when the widget payload actually changed.
        guard days != lastWidgetDays else { return }
        lastWidgetDays = days
        let snapshot = MemdoWidgetSnapshot(updatedAt: now, days: days)
        assert(days == days.sorted { $0.date < $1.date })
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: MemdoWidgetStorage.suiteName)?.set(data, forKey: MemdoWidgetStorage.snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

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
