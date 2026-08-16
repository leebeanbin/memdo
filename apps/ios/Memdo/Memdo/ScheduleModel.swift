import Foundation
import Observation
import Supabase
import WidgetKit

enum ScheduleKind: String, CaseIterable, Identifiable, Codable {
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

struct ScheduleCalendar: Identifiable, Equatable, Hashable, Codable {
    enum Provider: String, Codable {
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

enum ScheduleRepeatRule: String, CaseIterable, Identifiable, Codable {
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

enum ScheduleStatus: String, Codable {
    case planned
    case inProgress = "in_progress"
    case partial
    case completed
    case skipped
    case rescheduled
    case cancelled
}

enum ScheduleTimeBucket: String, CaseIterable, Identifiable, Codable {
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

struct ScheduleUserCategory: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var emoji: String
    var color: ScheduleColor
    var isTaskKind: Bool

    private static let storageKey = "memdo.v1.userCategories"

    static func load() -> [ScheduleUserCategory] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cats = try? JSONDecoder().decode([ScheduleUserCategory].self, from: data)
        else { return [] }
        return cats
    }

    static func persist(_ cats: [ScheduleUserCategory]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(cats), forKey: storageKey)
    }
}

enum ScheduleColor: String, CaseIterable, Identifiable, Codable {
    case coral
    case amber
    case sage
    case sky
    case indigo
    case violet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coral: "코랄"
        case .amber: "앰버"
        case .sage: "세이지"
        case .sky: "스카이"
        case .indigo: "인디고"
        case .violet: "바이올렛"
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

struct ScheduleLocation: Equatable, Codable {
    enum Provider: String, Codable {
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

struct ScheduleDetail: Identifiable, Equatable, Codable {
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
    /// Non-nil when this item belongs to a recurring rule (shown as a repeat badge).
    var scheduleRuleId: String?
    var color: ScheduleColor?
    var emoji: String?
    var estimatedMinutes: Int?
    /// Dedicated meeting-link field. Takes priority over links embedded in memo/location.
    /// Stored separately so MCP (and future integrations) can write a clean URL without
    /// touching the note text.
    var meetingURLString: String?
    /// True for a computed-but-not-yet-materialized recurring event occurrence
    /// (event-mode rules materialize nothing up front -- see ScheduleAPI's
    /// virtual occurrence handling). Saving/completing/deleting one must create
    /// the real row first (ScheduleStore routes this transparently).
    var isVirtual: Bool

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
        version: Int = 1,
        scheduleRuleId: String? = nil,
        color: ScheduleColor? = nil,
        emoji: String? = nil,
        estimatedMinutes: Int? = nil,
        meetingURLString: String? = nil,
        isVirtual: Bool = false
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
        self.scheduleRuleId = scheduleRuleId
        self.color = color
        self.emoji = emoji
        self.estimatedMinutes = estimatedMinutes
        self.meetingURLString = meetingURLString.flatMap { $0.isEmpty ? nil : $0 }
        self.isVirtual = isVirtual
    }

    var source: String { calendar.provider.displayName }
    var isExternal: Bool { calendar.provider == .google }
    // Rescheduled/cancelled/skipped entries are kept for history but hidden from
    // the active lists so a moved item doesn't leave a ghost on its old day.
    var isActive: Bool { status != .rescheduled && status != .cancelled && status != .skipped }
    var isReschedulable: Bool { status == .planned || status == .inProgress || status == .partial }
    /// True if this schedule is happening on `date` -- either it's the scheduled
    /// day, or (for a timed event) `date` falls within its start...end span, so a
    /// multi-day event shows on every day it covers, not just its start day.
    func occurs(on date: Date) -> Bool {
        let calendar = Calendar.current
        if calendar.isDate(scheduledDate, inSameDayAs: date) { return true }
        guard kind == .event, let startAt, let endAt else { return false }
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return startAt < dayEnd && endAt > dayStart
    }
    /// Any valid URL stored in the dedicated link field (meetings, docs, any URL).
    var linkURL: URL? { meetingURLString.flatMap(URL.init(string:)) }

    /// First recognised video-meeting link. Checks the dedicated field first so MCP
    /// and future integrations can write a clean URL; falls back to scanning memo/location.
    var meetingURL: URL? {
        if let stored = meetingURLString, let url = URL(string: stored), MeetingProvider.recognized(url) != nil {
            return url
        }
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
    /// `timeSortKey` clamped to `day` -- a multi-day event's absolute `startAt`
    /// (its first day) would otherwise sort before every same-day item on every
    /// later day it spans, pinning it to the top. Note: display text (e.g. in
    /// ScheduleRow) still shows the event's absolute start/end regardless of
    /// which spillover day it's rendered on -- a known follow-up, not fixed here.
    func timeSortKey(on day: Date) -> Date {
        guard kind == .event, let startAt, !Calendar.current.isDate(startAt, inSameDayAs: day) else {
            return timeSortKey
        }
        return Calendar.current.startOfDay(for: day)
    }
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
    private let outbox: OutboxStore
    private var networkMonitor: NetworkMonitor?
    private var isDraining = false

    func isPending(_ id: UUID) -> Bool {
        pendingWriteIDs.contains(id)
    }

    func dismissWriteError() {
        lastWriteError = nil
    }

    init(repository: ScheduleRepository, outbox: OutboxStore = OutboxStore()) {
        self.repository = repository
        self.outbox = outbox
        networkMonitor = NetworkMonitor { [weak self] in
            Task { @MainActor in await self?.drainOutbox() }
        }
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
    func googleCalendarStart() async throws -> URL {
        try await repository.googleCalendarStart()
    }

    func googleCalendarStatus() async throws -> GoogleCalendarStatusResponseDTO {
        try await repository.googleCalendarStatus()
    }

    /// Reloads afterward so the synthetic "Google Calendar" entry and any
    /// mirrored events disappear from the store immediately, rather than
    /// lingering until the next unrelated load().
    func googleCalendarDisconnect() async throws {
        try await repository.googleCalendarDisconnect()
        state = .idle
        await load()
    }

    func agentKeyConnected() async throws -> Bool {
        try await repository.agentKeyConnected()
    }

    func saveAgentKey(_ apiKey: String) async throws {
        try await repository.saveAgentKey(apiKey)
    }

    func deleteAgentKey() async throws {
        try await repository.deleteAgentKey()
    }

    func agentCloudChat(message: String, history: [AgentChatTurnDTO]) async throws -> AgentChatResponseDTO {
        try await repository.agentCloudChat(message: message, history: history)
    }

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
            .filter { $0.isActive && $0.occurs(on: date) }
            .sorted { $0.timeSortKey(on: date) < $1.timeSortKey(on: date) }
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
            // Replays anything queued from a previous session that was killed
            // while offline. The network-monitor trigger alone can't cover
            // this: its first callback can fire before `state` becomes
            // `.loaded`, at which point drainOutbox() is a deliberate no-op.
            await drainOutbox()
            await syncUserCategories()
            // UNCalendarNotificationTrigger with repeats:false is one-shot.
            // Rebuild all upcoming per-schedule reminders after every full load
            // so app restarts don't silently drop pending reminders.
            await refreshUpcomingReminders()
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
            // hasMore/nextCursor come from the server; this cap is just cheap
            // insurance against a future backend bug turning this into an
            // infinite loop, not something reachable today.
            var pagesFetched = 0
            let maxPages = 200
            while hasMore && pagesFetched < maxPages {
                pagesFetched += 1
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

    /// Replays writes that failed offline (see `ScheduleAPIError.offline`),
    /// oldest first. Stops -- rather than erroring -- the moment a replay
    /// fails offline again, leaving the rest queued for the next reconnect.
    /// A replay that fails for a real reason (e.g. a version conflict from
    /// an edit made on another device while this one was offline) is dropped
    /// and reconciled via refresh() instead of retried forever.
    func drainOutbox() async {
        guard !isDraining, state == .loaded else { return }
        isDraining = true
        defer { isDraining = false }

        for entry in await outbox.all() {
            do {
                switch entry.operation {
                case .create(let schedule):
                    replaceOrAppend(try await repository.create(schedule))
                case .update(let schedule):
                    replaceOrAppend(try await repository.update(schedule))
                case .delete(let id, let version):
                    try await repository.delete(id: id, version: version)
                case .reschedule(let original, let moved, let baseVersion):
                    let result = try await repository.reschedule(moved, baseVersion: baseVersion)
                    schedules.removeAll { $0.id == original.id }
                    schedules.append(result.original)
                    schedules.append(result.replacement)
                case .materializeThenDelete(let schedule):
                    let real = try await repository.create(schedule)
                    try await repository.delete(real)
                    schedules.removeAll { $0.id == schedule.id }
                case .materializeThenReschedule(let original, let moved):
                    let real = try await repository.create(original)
                    let result = try await repository.reschedule(moved, baseVersion: real.version)
                    schedules.removeAll { $0.id == original.id }
                    schedules.append(result.original)
                    schedules.append(result.replacement)
                }
                await outbox.remove(entry.scheduleID)
            } catch ScheduleAPIError.offline {
                break
            } catch {
                await outbox.remove(entry.scheduleID)
                lastWriteError = error.localizedDescription
            }
        }
        updateWidgetSnapshot()
        await refresh()
    }

    private func replaceOrAppend(_ schedule: ScheduleDetail) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
    }

    /// Pulls the backend's category set into the local cache (see
    /// ScheduleUserCategory.load/persist) so AddScheduleSheet's synchronous,
    /// offline-friendly reads stay current across devices. If the backend
    /// has nothing yet but a local cache already exists -- true the first
    /// time this runs against an account created before categories synced --
    /// pushes the local set up once instead of silently wiping it.
    private func syncUserCategories() async {
        do {
            let remote = try await repository.loadCategories()
            if remote.isEmpty {
                let local = ScheduleUserCategory.load()
                if !local.isEmpty {
                    _ = try? await repository.replaceCategories(local)
                }
            } else {
                ScheduleUserCategory.persist(remote)
            }
        } catch {
            // Best-effort -- the local cache still works offline either way.
        }
    }

    /// Persists a category edit locally (instant, offline-friendly, matching
    /// how AddScheduleSheet already reads via ScheduleUserCategory.load())
    /// and pushes the full replacement set to the backend in the background.
    func replaceUserCategories(_ categories: [ScheduleUserCategory]) {
        ScheduleUserCategory.persist(categories)
        Task { _ = try? await repository.replaceCategories(categories) }
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

    /// Deletes the whole recurring series from today on (past occurrences stay
    /// as history), then reloads so the cleared occurrences disappear.
    func deleteRecurring(ruleId: String) {
        Task {
            do {
                try await repository.deleteRule(id: ruleId)
                await load()
            } catch {
                lastWriteError = error.localizedDescription
            }
        }
    }

    func save(_ schedule: ScheduleDetail) {
        // Always reschedule the reminder, even when a concurrent write is already
        // in-flight. The guard below deduplicates network writes only.
        Task { await NotificationScheduler.scheduleReminder(for: schedule) }
        Task { await NotificationScheduler.scheduleEndNotification(for: schedule) }
        guard !pendingWriteIDs.contains(schedule.id) else { return }
        pendingWriteIDs.insert(schedule.id)
        // A virtual occurrence (event-mode rule, computed but never written to the
        // DB) has no real row to PATCH -- regardless of whether it's already in
        // `schedules` locally (it got there via the same GET that computed it).
        if schedule.isVirtual {
            if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
                schedules[index] = schedule
            } else {
                schedules.append(schedule)
            }
            updateWidgetSnapshot()
            Task {
                await create(schedule)
                pendingWriteIDs.remove(schedule.id)
            }
            return
        }
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
                await create(schedule, notifyOnSuccess: true)
                pendingWriteIDs.remove(schedule.id)
            }
        }
    }

    /// `notifyOnSuccess` is only true for a genuinely new, user-initiated
    /// schedule (see save(_:)) -- create() is also the materialize step for
    /// touching a virtual recurring occurrence, which isn't "a new schedule"
    /// from the user's perspective and shouldn't announce itself as one.
    private func create(_ schedule: ScheduleDetail, notifyOnSuccess: Bool = false) async {
        let saved: ScheduleDetail
        do {
            saved = try await repository.create(schedule)
        } catch ScheduleAPIError.offline {
            // Keep the optimistic row as-is (it's already in `schedules`) and
            // queue the create for replay -- no rollback, no error shown.
            await outbox.enqueue(.create(schedule), scheduleID: schedule.id)
            return
        } catch {
            if schedule.isVirtual {
                // This wasn't a net-new item -- it's a computed occurrence that
                // still exists (the server will recompute it as virtual again on
                // the next list). Restore the pre-edit value instead of erasing
                // it; removing it here would just make the recurring occurrence
                // vanish from every list/widget until a full reload.
                if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
                    schedules[index] = schedule
                } else {
                    schedules.append(schedule)
                }
            } else {
                // Nothing exists server-side yet -- safe to drop the optimistic entry.
                schedules.removeAll { $0.id == schedule.id }
            }
            updateWidgetSnapshot()
            lastWriteError = error.localizedDescription
            return
        }
        // The row is real now regardless of what happens below -- keep it that
        // way even if the follow-up fails, so a retry goes through update()'s
        // PATCH path rather than create() again (which would now 409 on the id
        // it already owns).
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = saved
        } else {
            schedules.append(saved)
        }
        updateWidgetSnapshot()
        // Fires only now that the row is confirmed persisted -- not
        // optimistically at the start of save(), which could announce a
        // schedule that then fails validation or a conflict and never exists.
        if notifyOnSuccess {
            await SlackNotifier.notify(schedule: saved, event: .created)
        }
        // POST /todos (create) doesn't accept a status -- new rows always start
        // "planned" server-side. If the caller's intent was e.g. completing a
        // virtual occurrence in one action, follow up with the real row's status
        // now that it has a real version to optimistically-lock against.
        guard saved.status != schedule.status else { return }
        do {
            var desired = saved
            desired.status = schedule.status
            let updated = try await repository.update(desired)
            if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
                schedules[index] = updated
            } else {
                schedules.append(updated)
            }
            updateWidgetSnapshot()
        } catch {
            lastWriteError = error.localizedDescription
        }
    }

    private func update(_ schedule: ScheduleDetail, replacing previous: ScheduleDetail) async {
        do {
            replace(schedule.id, with: try await repository.update(schedule))
        } catch ScheduleAPIError.offline {
            // Optimistic value in `schedules` already reflects the edit --
            // leave it and queue the PATCH for replay.
            await outbox.enqueue(.update(schedule), scheduleID: schedule.id)
            return
        } catch {
            replace(schedule.id, with: previous)
            lastWriteError = error.localizedDescription
            updateWidgetSnapshot()
            return
        }
        updateWidgetSnapshot()
        // Fires only now that the completion is confirmed persisted -- not
        // optimistically when the toggle was tapped, which could announce a
        // completion that a validation/conflict error then rolls back.
        if schedule.isDone && !previous.isDone {
            await SlackNotifier.notify(schedule: schedule, event: .completed)
        }
    }

    func reset() {
        schedules = []
        calendars = []
        state = .idle
        lastSyncCursor = nil
        loadedFrom = nil
        loadedTo = nil
        // hideWidgetContent is a per-user privacy preference; it shouldn't carry
        // over to whichever account signs in next on this device.
        UserDefaults(suiteName: MemdoWidgetStorage.suiteName)?
            .removeObject(forKey: MemdoWidgetStorage.hideContentKey)
        updateWidgetSnapshot()
    }

    private func replace(_ id: UUID, with schedule: ScheduleDetail) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index] = schedule
    }

    func toggleDone(id: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == id }),
              schedules[index].kind == .task else { return }
        // Update local state immediately so the ring reflects the change even
        // when save() returns early due to a concurrent in-flight write.
        schedules[index].isDone.toggle()
        updateWidgetSnapshot()
        save(schedules[index])
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
        // `moved` keeps `original`'s id, so materializing first (same pattern as
        // delete()) then rescheduling with the real version works transparently.
        // Tracked separately so a later failure can roll back to the now-real
        // row instead of the stale virtual one -- retrying against a virtual
        // value would re-POST and 409 on the id it already owns.
        var materialized: ScheduleDetail?
        do {
            let baseVersion: Int
            if original.isVirtual {
                let real = try await repository.create(original)
                materialized = real
                baseVersion = real.version
            } else {
                baseVersion = original.version
            }
            let result = try await repository.reschedule(moved, baseVersion: baseVersion)
            schedules.removeAll { $0.id == original.id }
            schedules.append(result.original)
            schedules.append(result.replacement)
            updateWidgetSnapshot()
            // Original is now "rescheduled" status — cancel its reminder.
            // Replacement is a new entry on the new date — schedule its reminder.
            NotificationScheduler.cancelReminder(for: original.id)
            NotificationScheduler.cancelEndNotification(for: original.id)
            await NotificationScheduler.scheduleReminder(for: result.replacement)
            await NotificationScheduler.scheduleEndNotification(for: result.replacement)
        } catch ScheduleAPIError.offline {
            // `schedules` already shows `moved` optimistically -- leave it and
            // queue replay. If materialize landed before the drop, replay just
            // the reschedule against the now-real row; otherwise redo both.
            if let materialized {
                await outbox.enqueue(
                    .reschedule(original: materialized, moved: moved, baseVersion: materialized.version),
                    scheduleID: original.id
                )
            } else {
                await outbox.enqueue(.materializeThenReschedule(original: original, moved: moved), scheduleID: original.id)
            }
            return
        } catch {
            if let index = schedules.firstIndex(where: { $0.id == original.id }) {
                schedules[index] = materialized ?? original
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
        NotificationScheduler.cancelReminder(for: id)
        NotificationScheduler.cancelEndNotification(for: id)
        pendingWriteIDs.insert(id)
        Task {
            await delete(schedule)
            pendingWriteIDs.remove(id)
        }
    }

    private func delete(_ schedule: ScheduleDetail) async {
        // Tracked separately so a later failure restores the now-real row
        // instead of the stale virtual one -- retrying delete against a virtual
        // value would re-POST and 409 on the id it already owns.
        var materialized: ScheduleDetail?
        do {
            if schedule.isVirtual {
                // No real row exists yet to delete -- materialize it first (so the
                // series knows this date is spoken for) and delete that.
                let real = try await repository.create(schedule)
                materialized = real
                try await repository.delete(real)
            } else {
                try await repository.delete(schedule)
            }
        } catch ScheduleAPIError.offline {
            // Optimistic removal from `schedules` already happened in
            // delete(id:) -- leave it removed and queue replay.
            if let materialized {
                await outbox.enqueue(
                    .delete(id: materialized.id, version: materialized.version),
                    scheduleID: schedule.id
                )
            } else {
                await outbox.enqueue(.materializeThenDelete(schedule), scheduleID: schedule.id)
            }
            return
        } catch {
            // Restore by identity, not a stale index — other optimistic edits may
            // have shifted positions. Lists re-sort by timeSortKey on read.
            if !schedules.contains(where: { $0.id == schedule.id }) {
                schedules.append(materialized ?? schedule)
            }
            updateWidgetSnapshot()
            lastWriteError = error.localizedDescription
        }
    }

    private func refreshUpcomingReminders() async {
        let now = Date.now
        let upcoming = schedules.filter { s in
            s.isActive && s.startAt.map { $0 > now } == true
        }
        for schedule in upcoming {
            if schedule.reminderOffsetMinutes != nil {
                await NotificationScheduler.scheduleReminder(for: schedule)
            }
            await NotificationScheduler.scheduleEndNotification(for: schedule)
        }
    }

    private func updateWidgetSnapshot() {
        let calendar = Calendar.current
        let now = Date.now
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .month, value: 2, to: start) ?? now
        // Scans day by day (matching CalendarView.scheduleCounts) rather than
        // grouping by exact scheduledDate, so a multi-day event appears on every
        // day it spans, not just its start day. `schedules` is unbounded (grows
        // with ensureLoaded() and is never evicted) and this runs on every
        // write, so pre-filter to what could possibly intersect [start, end)
        // before the O(days) scan rather than re-scanning everything per day.
        let candidates = schedules.filter { $0.scheduledDate < end && ($0.endAt ?? $0.scheduledDate) >= start }
        var days: [MemdoWidgetDay] = []
        var day = start
        while day < end {
            let dayCandidates = candidates.filter { $0.occurs(on: day) }
            if !dayCandidates.isEmpty {
                let sorted = dayCandidates.sorted { $0.timeSortKey(on: day) < $1.timeSortKey(on: day) }
                days.append(MemdoWidgetDay(
                    date: day,
                    completedCount: sorted.filter(\.isDone).count,
                    items: sorted.filter(\.isWidgetActive).map {
                        MemdoWidgetItem(
                            id: $0.id,
                            time: $0.startTimeText,
                            title: $0.title,
                            kind: $0.kind.rawValue,
                            color: $0.color?.rawValue
                        )
                    }
                ))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
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
