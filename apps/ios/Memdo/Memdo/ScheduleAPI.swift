import Foundation
import Supabase

struct DayViewResponseDTO: Decodable {
    let date: String
    let todos: [TodoResponseDTO]
    let emptyState: String
    let needsReviewCount: Int
}

struct CalendarResponseDTO: Decodable {
    let id: String
    let name: String
    let purpose: String
    let colorToken: String?
    let isVisible: Bool
    let sortOrder: Int
    let provider: String?

    var scheduleCalendar: ScheduleCalendar {
        ScheduleCalendar(
            id: id,
            title: name,
            purpose: purpose,
            provider: ScheduleCalendar.Provider(rawValue: provider ?? "memdo") ?? .memdo
        )
    }
}

struct GoogleCalendarStartResponseDTO: Decodable {
    let authorizationUrl: String
}

struct GoogleCalendarStatusResponseDTO: Decodable {
    let connected: Bool
    let status: String
    let calendarId: String?
    let lastSyncedAt: String?
    let lastError: String?
}

struct GoogleCalendarDisconnectResponseDTO: Decodable {
    let connected: Bool
}

// ScheduleUserCategory's stored properties (id/name/emoji/color/isTaskKind)
// already match /categories' DTO shape field-for-field -- no separate DTO
// struct needed, it's sent and received directly.
struct CategoriesResponseDTO: Decodable {
    let items: [ScheduleUserCategory]
}

struct CategoriesReplaceRequestDTO: Encodable {
    let categories: [ScheduleUserCategory]
}

/// Sent to apple-auth-token-exchange right after a successful Sign in with
/// Apple -- the authorizationCode is single-use/short-lived (~5 minutes),
/// so this must happen at sign-in time, not lazily later.
struct AppleAuthTokenExchangeRequestDTO: Encodable {
    let authorizationCode: String
}

struct AppleAuthTokenExchangeResponseDTO: Decodable {
    let linked: Bool
}

/// Matches DELETE /account's request body (docs/05-api-spec.yaml,
/// memdo-backend) -- a typed confirmation string, not just the DELETE verb
/// itself, as an extra guard against an accidental/automated call.
struct AccountDeletionRequestDTO: Encodable {
    let confirmation: String
}

struct AccountDeletionResponseDTO: Decodable {
    let deleted: Bool
}

/// Mirrors reviews/index.ts's reviewDto -- `reflection` can be nil (a row
/// exists with no reflection text set), distinct from no row existing at
/// all (review(date:accessToken:) returns nil for that case).
struct ReviewDTO: Decodable, Equatable {
    let reviewDate: String
    let reflection: String?
    let createdAt: String
    let updatedAt: String
}

struct ReviewInputDTO: Encodable {
    let reflection: String
}

struct TodoListResponseDTO: Decodable {
    let items: [TodoResponseDTO]
    let nextCursor: String?
    let hasMore: Bool
}

private struct DemoBootstrapRequestDTO: Encodable {
    let localDate: String
    let timezoneOffsetMinutes: Int
}

private struct DemoBootstrapResponseDTO: Decodable {
    let seededCount: Int
}

struct LocationDTO: Codable {
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let provider: String?
    let providerId: String?
}

struct TodoResponseDTO: Decodable {
    let id: String
    let scheduledDate: String
    let calendarId: String
    let title: String
    let entryKind: String
    let isAllDay: Bool
    let note: String?
    let startAt: String?
    let endAt: String?
    let dueAt: String?
    let location: LocationDTO?
    let timeBucket: String
    let reminderOffsetMinutes: Int?
    let sortOrder: Int
    let status: String
    let version: Int
    let scheduleRuleId: String?
    // Optional (bd18) for the same reason isVirtual is -- a build shipped
    // before the backend deploys the field must still decode the list.
    let categoryId: String?
    let color: String?
    let emoji: String?
    let estimatedMinutes: Int?
    let meetingUrl: String?
    // Optional (defaults false at the mapping site below) so a build that
    // ships before the backend deploys the field doesn't hard-fail decoding
    // the entire todos list over one missing key.
    let isVirtual: Bool?
}

struct TodoCreateRequestDTO: Encodable {
    let scheduledDate: String
    let calendarId: String
    let title: String
    let entryKind: String
    let isAllDay: Bool
    let note: String?
    let startAt: String?
    let endAt: String?
    let dueAt: String?
    let location: LocationDTO?
    let timeBucket: String
    let sortOrder: Int
    let reminderOffsetMinutes: Int?
    let version: Int?
    let status: String?
    let scheduleRuleId: String?
    let categoryId: String?
    let color: String?
    let emoji: String?
    let estimatedMinutes: Int?
    let meetingUrl: String?

    init(schedule: ScheduleDetail, includeVersion: Bool = false) throws {
        guard UUID(uuidString: schedule.calendar.id) != nil else {
            throw ScheduleAPIError.invalidCalendar
        }
        guard schedule.isTimeRangeValid else {
            throw ScheduleAPIError.invalidSchedule
        }

        scheduledDate = APIDate.day(schedule.scheduledDate)
        calendarId = schedule.calendar.id
        title = schedule.title.trimmingCharacters(in: .whitespacesAndNewlines)
        entryKind = schedule.kind.rawValue
        isAllDay = schedule.isAllDay
        note = schedule.memo.isEmpty ? nil : schedule.memo
        startAt = schedule.startAt.map(APIDate.instant)
        endAt = schedule.endAt.map(APIDate.instant)
        dueAt = schedule.kind == .task ? schedule.dueAt.map(APIDate.instant) : nil
        location = schedule.locationValue.map {
            LocationDTO(
                name: $0.name,
                address: $0.address,
                latitude: $0.latitude,
                longitude: $0.longitude,
                provider: $0.provider?.rawValue,
                providerId: $0.providerID
            )
        }
        timeBucket = schedule.timeBucket.rawValue
        sortOrder = schedule.sortOrder
        reminderOffsetMinutes = schedule.reminderOffsetMinutes
        version = includeVersion ? schedule.version : nil
        status = includeVersion ? schedule.status.rawValue : nil
        scheduleRuleId = schedule.scheduleRuleId
        categoryId = schedule.categoryId?.uuidString
        color = schedule.color?.rawValue
        emoji = schedule.emoji.flatMap { $0.isEmpty ? nil : $0 }
        estimatedMinutes = schedule.kind == .task ? schedule.estimatedMinutes : nil
        meetingUrl = schedule.meetingURLString.flatMap { $0.isEmpty ? nil : $0 }
    }
}

private struct TodoDeleteRequestDTO: Encodable {
    let version: Int
}

private struct TodoDeleteResponseDTO: Decodable {
    let id: String
}

struct TodoRescheduleRequestDTO: Encodable {
    let baseVersion: Int
    let targetDate: String
    let startAt: String?
    let endAt: String?
    let dueAt: String?
    let timeBucket: String

    init(schedule: ScheduleDetail, baseVersion: Int) {
        self.baseVersion = baseVersion
        targetDate = APIDate.day(schedule.scheduledDate)
        startAt = schedule.startAt.map(APIDate.instant)
        endAt = schedule.endAt.map(APIDate.instant)
        dueAt = schedule.kind == .task ? schedule.dueAt.map(APIDate.instant) : nil
        timeBucket = schedule.timeBucket.rawValue
    }

    // `todoRescheduleSchema`'s startAt/endAt/dueAt are `.nullable()` WITHOUT
    // `.optional()` -- the key must be present, even as `null`. The compiler-
    // synthesized Encodable conformance uses encodeIfPresent for Optional
    // properties, which omits a nil key entirely instead of writing `null`,
    // so every reschedule of a non-task item (dueAt always nil above) failed
    // server validation with "dueAt: expected string, received undefined"
    // (confirmed via live device request/response logging).
    private enum CodingKeys: String, CodingKey {
        case baseVersion, targetDate, startAt, endAt, dueAt, timeBucket
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseVersion, forKey: .baseVersion)
        try container.encode(targetDate, forKey: .targetDate)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encode(dueAt, forKey: .dueAt)
        try container.encode(timeBucket, forKey: .timeBucket)
    }
}

private struct TodoRescheduleResponseDTO: Decodable {
    let original: TodoResponseDTO
    let replacement: TodoResponseDTO
}

// bd26: entityType-aware -- /sync now merges todos, workout_logs, and
// user_categories into one sync_seq-ordered stream. `data`'s shape depends
// on entityType, so a plain synthesized Decodable (trying to decode `data`
// as TodoResponseDTO regardless) would throw on a non-todo item and fail
// the whole page's decode. Each store reads only its own *Data property and
// ignores items it doesn't recognize rather than erroring. ScheduleUserCategory
// already matches /categories' DTO shape field-for-field (see
// CategoriesResponseDTO's comment), so it's reused directly here too.
struct SyncItemDTO: Decodable {
    let entityType: String
    let operation: String
    let id: String
    let todoData: TodoResponseDTO?
    let workoutData: WorkoutLogResponseDTO?
    let categoryData: ScheduleUserCategory?

    private enum CodingKeys: String, CodingKey {
        case entityType, operation, id, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityType = try container.decode(String.self, forKey: .entityType)
        operation = try container.decode(String.self, forKey: .operation)
        id = try container.decode(String.self, forKey: .id)
        switch entityType {
        case "workout":
            todoData = nil
            categoryData = nil
            workoutData = try container.decodeIfPresent(WorkoutLogResponseDTO.self, forKey: .data)
        case "category":
            todoData = nil
            workoutData = nil
            categoryData = try container.decodeIfPresent(ScheduleUserCategory.self, forKey: .data)
        default:
            todoData = try container.decodeIfPresent(TodoResponseDTO.self, forKey: .data)
            workoutData = nil
            categoryData = nil
        }
    }
}

struct SyncResponseDTO: Decodable {
    let items: [SyncItemDTO]
    let nextCursor: String?
    let hasMore: Bool
}

struct SearchResponseDTO: Decodable {
    let items: [TodoResponseDTO]
    let hasMore: Bool
}

struct ScheduleRuleRequestDTO: Encodable {
    let calendarId: String
    let title: String
    let entryKind: String
    let isAllDay: Bool
    let note: String?
    let startTime: String?
    let endTime: String?
    let timeBucket: String
    let reminderOffsetMinutes: Int?
    let frequency: String
    let interval: Int
    let anchorDate: String
    // bd16: was a raw minute offset (TimeZone.current.secondsFromGMT), frozen
    // at rule-creation time and reused unchanged for every future occurrence
    // -- wrong at a DST transition for any timezone that observes one. The
    // backend now stores this IANA identifier and computes each occurrence's
    // own offset from it at materialization time instead.
    let timezone: String

    init(schedule: ScheduleDetail) {
        calendarId = schedule.calendar.id
        title = schedule.title.trimmingCharacters(in: .whitespacesAndNewlines)
        entryKind = schedule.kind.rawValue
        isAllDay = schedule.isAllDay
        note = schedule.memo.isEmpty ? nil : schedule.memo
        startTime = schedule.startAt.map(Self.clock)
        endTime = schedule.endAt.map(Self.clock)
        timeBucket = schedule.timeBucket.rawValue
        reminderOffsetMinutes = schedule.reminderOffsetMinutes
        frequency = schedule.repeatRule.rawValue
        interval = 1
        anchorDate = APIDate.day(schedule.scheduledDate)
        timezone = TimeZone.current.identifier
    }

    private static func clock(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

private struct ScheduleRuleResponseDTO: Decodable {
    let occurrenceCount: Int
}

private struct ScheduleRuleDeleteResponseDTO: Decodable {
    let id: String
}

enum ScheduleAPIError: Error, LocalizedError {
    case missingConfiguration
    case notAuthenticated
    case invalidCalendar
    case invalidSchedule
    case invalidResponse
    case incompatibleValue(String)
    case server(status: Int, code: String, message: String, requestID: String?)
    /// The request never reached the server -- no connection, a dropped
    /// connection, or a timeout. Distinguished from `.server` so callers can
    /// queue-and-retry instead of treating it as a real rejection.
    case offline(URLError)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: "Supabase URL과 publishable key를 설정해 주세요."
        case .notAuthenticated: "로그인이 필요합니다."
        case .invalidCalendar: "서버 캘린더를 먼저 선택해 주세요."
        case .invalidSchedule: "일정 기간을 확인해 주세요."
        case .invalidResponse: "서버 응답을 읽을 수 없습니다."
        case .incompatibleValue(let value): "지원하지 않는 서버 값입니다: \(value)"
        case .server(_, _, let message, _): message
        case .offline: "오프라인 상태예요. 연결되면 자동으로 저장돼요."
        }
    }
}

private let offlineURLErrorCodes: Set<URLError.Code> = [
    .notConnectedToInternet,
    .networkConnectionLost,
    .timedOut,
    .cannotConnectToHost,
    .cannotFindHost,
    .dnsLookupFailed,
    .dataNotAllowed,
    .internationalRoamingOff,
]

actor MemdoAPIClient {
    private let functionsURL: URL
    private let publishableKey: String
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(projectURL: URL, publishableKey: String, session: URLSession = .shared) {
        functionsURL = projectURL.appending(path: "functions/v1")
        self.publishableKey = publishableKey
        self.session = session
    }

    func calendars(accessToken: String) async throws -> [CalendarResponseDTO] {
        try await send(path: "calendars", accessToken: accessToken)
    }

    func day(on date: Date, accessToken: String) async throws -> DayViewResponseDTO {
        try await send(path: "days/\(APIDate.day(date))", accessToken: accessToken)
    }

    func todos(from: Date, to: Date, accessToken: String) async throws -> [TodoResponseDTO] {
        var items: [TodoResponseDTO] = []
        var cursor: String?
        repeat {
            let page: TodoListResponseDTO = try await send(
                path: "todos",
                queryItems: [
                    URLQueryItem(name: "from", value: APIDate.day(from)),
                    URLQueryItem(name: "to", value: APIDate.day(to)),
                    URLQueryItem(name: "limit", value: "50"),
                    URLQueryItem(name: "cursor", value: cursor)
                ],
                accessToken: accessToken
            )
            items.append(contentsOf: page.items)
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil
        return items
    }

    func bootstrapDemo(on date: Date, accessToken: String) async throws {
        let input = DemoBootstrapRequestDTO(
            localDate: APIDate.day(date),
            timezoneOffsetMinutes: TimeZone.current.secondsFromGMT(for: date) / 60
        )
        let _: DemoBootstrapResponseDTO = try await send(
            path: "demo-bootstrap",
            method: "POST",
            body: encoder.encode(input),
            accessToken: accessToken
        )
    }

    func create(
        _ input: TodoCreateRequestDTO,
        idempotencyKey: UUID,
        accessToken: String
    ) async throws -> TodoResponseDTO {
        try await send(
            path: "todos",
            method: "POST",
            body: encoder.encode(input),
            idempotencyKey: idempotencyKey,
            accessToken: accessToken
        )
    }

    func update(_ schedule: ScheduleDetail, accessToken: String) async throws -> TodoResponseDTO {
        try await send(
            path: "todos/\(schedule.id.uuidString)",
            method: "PATCH",
            body: encoder.encode(TodoCreateRequestDTO(schedule: schedule, includeVersion: true)),
            accessToken: accessToken
        )
    }

    func delete(id: UUID, version: Int, accessToken: String) async throws {
        let _: TodoDeleteResponseDTO = try await send(
            path: "todos/\(id.uuidString)",
            method: "DELETE",
            body: encoder.encode(TodoDeleteRequestDTO(version: version)),
            accessToken: accessToken
        )
    }

    func reschedule(
        id: UUID,
        input: TodoRescheduleRequestDTO,
        idempotencyKey: UUID,
        accessToken: String
    ) async throws -> (original: TodoResponseDTO, replacement: TodoResponseDTO) {
        let response: TodoRescheduleResponseDTO = try await send(
            path: "todos/\(id.uuidString)/reschedule",
            method: "POST",
            body: encoder.encode(input),
            idempotencyKey: idempotencyKey,
            accessToken: accessToken
        )
        return (response.original, response.replacement)
    }

    func sync(cursor: String?, accessToken: String) async throws -> SyncResponseDTO {
        try await send(
            path: "sync",
            queryItems: [
                URLQueryItem(name: "cursor", value: cursor),
                URLQueryItem(name: "limit", value: "200")
            ],
            accessToken: accessToken
        )
    }

    func search(query: String, accessToken: String) async throws -> SearchResponseDTO {
        try await send(
            path: "search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "50")
            ],
            accessToken: accessToken
        )
    }

    func createRule(_ input: ScheduleRuleRequestDTO, accessToken: String) async throws {
        let _: ScheduleRuleResponseDTO = try await send(
            path: "rules",
            method: "POST",
            body: encoder.encode(input),
            accessToken: accessToken
        )
    }

    // The server drops future, non-edited occurrences from localDate on and
    // keeps past ones as history, then removes the rule itself.
    func deleteRule(id: String, localDate: String, accessToken: String) async throws {
        let _: ScheduleRuleDeleteResponseDTO = try await send(
            path: "rules/\(id)",
            method: "DELETE",
            queryItems: [URLQueryItem(name: "localDate", value: localDate)],
            accessToken: accessToken
        )
    }

    func googleCalendarStart(accessToken: String) async throws -> GoogleCalendarStartResponseDTO {
        try await send(path: "google-calendar-start", method: "POST", accessToken: accessToken)
    }

    func googleCalendarStatus(accessToken: String) async throws -> GoogleCalendarStatusResponseDTO {
        try await send(path: "google-calendar-status", accessToken: accessToken)
    }

    func googleCalendarDisconnect(accessToken: String) async throws -> GoogleCalendarDisconnectResponseDTO {
        try await send(path: "google-calendar-disconnect", method: "POST", accessToken: accessToken)
    }

    func categories(accessToken: String) async throws -> CategoriesResponseDTO {
        try await send(path: "categories", accessToken: accessToken)
    }

    func replaceCategories(
        _ categories: [ScheduleUserCategory],
        accessToken: String
    ) async throws -> CategoriesResponseDTO {
        try await send(
            path: "categories",
            method: "PUT",
            body: encoder.encode(CategoriesReplaceRequestDTO(categories: categories)),
            accessToken: accessToken
        )
    }

    func agentKeyStatus(accessToken: String) async throws -> AgentKeyStatusResponseDTO {
        try await send(path: "agent-key", accessToken: accessToken)
    }

    func saveAgentKey(_ apiKey: String, accessToken: String) async throws -> AgentKeyStatusResponseDTO {
        try await send(
            path: "agent-key",
            method: "PUT",
            body: encoder.encode(AgentKeySaveRequestDTO(apiKey: apiKey)),
            accessToken: accessToken
        )
    }

    func deleteAgentKey(accessToken: String) async throws -> AgentKeyStatusResponseDTO {
        try await send(path: "agent-key", method: "DELETE", accessToken: accessToken)
    }

    func exchangeAppleAuthCode(
        _ authorizationCode: String,
        accessToken: String
    ) async throws -> AppleAuthTokenExchangeResponseDTO {
        try await send(
            path: "apple-auth-token-exchange",
            method: "POST",
            body: encoder.encode(AppleAuthTokenExchangeRequestDTO(authorizationCode: authorizationCode)),
            accessToken: accessToken
        )
    }

    func deleteAccount(accessToken: String) async throws -> AccountDeletionResponseDTO {
        try await send(
            path: "account",
            method: "DELETE",
            body: encoder.encode(AccountDeletionRequestDTO(confirmation: "DELETE")),
            accessToken: accessToken
        )
    }

    func agentModels(accessToken: String) async throws -> [AgentModelDTO] {
        let response: AgentModelsResponseDTO = try await send(
            path: "agent-models",
            accessToken: accessToken
        )
        return response.models
    }

    func agentUsage(days: Int, accessToken: String) async throws -> AgentUsageResponseDTO {
        try await send(
            path: "agent-usage",
            queryItems: [URLQueryItem(name: "days", value: String(days))],
            accessToken: accessToken
        )
    }

    /// nil ONLY for a 404 RESOURCE_NOT_FOUND (no reflection written for this
    /// date yet) -- every other error (a different server error, offline)
    /// propagates unchanged. Silently mapping any failure to "no reflection
    /// exists" would be worse than not checking at all for the overwrite-
    /// warning card that calls this: it could hide a real existing
    /// reflection from the user precisely when something went wrong reading it.
    func review(date: String, accessToken: String) async throws -> ReviewDTO? {
        do {
            return try await send(path: "reviews/\(date)", accessToken: accessToken)
        } catch ScheduleAPIError.server(404, "RESOURCE_NOT_FOUND", _, _) {
            return nil
        }
    }

    func putReview(date: String, reflection: String, accessToken: String) async throws -> ReviewDTO {
        try await send(
            path: "reviews/\(date)",
            method: "PUT",
            body: encoder.encode(ReviewInputDTO(reflection: reflection)),
            accessToken: accessToken
        )
    }

    /// agent-cloud-chat responds with newline-delimited JSON, not a single
    /// decodable body -- `onDelta` fires as text chunks arrive so the UI can
    /// update live the same way the on-device path's streamResponse already
    /// does, instead of the caller staring at a blank bubble until the whole
    /// (possibly multi-tool-call) turn finishes server-side.
    func agentCloudChat(
        message: String,
        history: [AgentChatTurnDTO],
        model: String?,
        accessToken: String,
        onDelta: @escaping @MainActor (String) -> Void,
        /// Fires for each `toolCallStarted` line, in order, as they arrive --
        /// a truthful live "tool is executing" signal (D4). Default no-op so
        /// existing call sites (tests, anything not wired to the toolHint
        /// pipeline yet) don't need updating.
        onToolCallStarted: @escaping @MainActor (String) -> Void = { _ in },
        /// Fires for each `toolCallFinished` line -- the truthful "clear the
        /// hint" signal (D4 second-pass review) a client needs so
        /// onToolCallStarted's hint doesn't outlive the tool call it
        /// describes.
        onToolCallFinished: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> AgentCloudChatResult {
        let url = functionsURL.appending(path: "agent-cloud-chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(
            AgentChatRequestDTO(message: message, history: history, model: model, debug: Self.debugTraceEnabled)
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let error as URLError where offlineURLErrorCodes.contains(error.code) {
            throw ScheduleAPIError.offline(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScheduleAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let error = try? decoder.decode(ErrorEnvelope.self, from: errorData).error
            throw ScheduleAPIError.server(
                status: httpResponse.statusCode,
                code: error?.code ?? "UNKNOWN",
                message: error?.message ?? "요청을 완료하지 못했습니다.",
                requestID: error?.requestId ?? httpResponse.value(forHTTPHeaderField: "X-Request-ID")
            )
        }

        var proposedSchedule: CloudProposedScheduleDTO?
        var proposedScheduleUpdate: CloudProposedScheduleUpdateDTO?
        var proposedRoutineUpdate: CloudProposedRoutineUpdateDTO?
        var proposedReviewAction: CloudProposedReviewActionDTO?
        var clarificationRequest: CloudClarificationRequestDTO?
        var toolNames: [String] = []
        var debugTrace: AgentDebugTraceDTO?
        for try await line in bytes.lines {
            guard let lineData = line.data(using: .utf8),
                  let parsed = try? decoder.decode(AgentStreamLineDTO.self, from: lineData) else { continue }
            if let delta = parsed.delta { await onDelta(delta) }
            if let toolCallStarted = parsed.toolCallStarted { await onToolCallStarted(toolCallStarted) }
            if let toolCallFinished = parsed.toolCallFinished { await onToolCallFinished(toolCallFinished) }
            if let streamError = parsed.error {
                throw ScheduleAPIError.server(
                    status: 502,
                    code: streamError.code,
                    message: streamError.message,
                    requestID: streamError.requestId
                )
            }
            if parsed.done == true {
                proposedSchedule = parsed.proposedSchedule
                proposedScheduleUpdate = parsed.proposedScheduleUpdate
                proposedRoutineUpdate = parsed.proposedRoutineUpdate
                proposedReviewAction = parsed.proposedReviewAction
                clarificationRequest = parsed.clarificationRequest
                toolNames = parsed.toolNames ?? []
                debugTrace = parsed.debugTrace
            }
        }
        return AgentCloudChatResult(
            proposedSchedule: proposedSchedule,
            proposedScheduleUpdate: proposedScheduleUpdate,
            proposedRoutineUpdate: proposedRoutineUpdate,
            proposedReviewAction: proposedReviewAction,
            clarificationRequest: clarificationRequest,
            toolNames: toolNames,
            debugTrace: debugTrace
        )
    }

    /// DEBUG-build-only, no runtime toggle -- a Release build never sends
    /// `debug: true`, so it never receives a detailed trace regardless of
    /// what the backend would otherwise include (D2).
    private static var debugTraceEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem] = [],
        idempotencyKey: UUID? = nil,
        accessToken: String
    ) async throws -> Response {
        var components = URLComponents(url: functionsURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.filter { $0.value != nil }
        guard let url = components?.url else { throw ScheduleAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if let idempotencyKey {
            request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where offlineURLErrorCodes.contains(error.code) {
            throw ScheduleAPIError.offline(error)
        }
        guard let response = response as? HTTPURLResponse else {
            throw ScheduleAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? decoder.decode(ErrorEnvelope.self, from: data).error
            throw ScheduleAPIError.server(
                status: response.statusCode,
                code: error?.code ?? "UNKNOWN",
                message: error?.message ?? "요청을 완료하지 못했습니다.",
                requestID: error?.requestId ?? response.value(forHTTPHeaderField: "X-Request-ID")
            )
        }
        return try decoder.decode(Response.self, from: data)
    }
}

struct ScheduleSnapshot {
    let schedules: [ScheduleDetail]
    let calendars: [ScheduleCalendar]
}

actor ScheduleRepository {
    private let auth: SupabaseClient
    private let api: MemdoAPIClient

    init(configuration: MemdoConfiguration, auth: SupabaseClient) {
        self.auth = auth
        api = MemdoAPIClient(
            projectURL: configuration.projectURL,
            publishableKey: configuration.publishableKey
        )
    }

    func load(around date: Date) async throws -> ScheduleSnapshot {
        let accessToken = try await accessToken()
        #if DEBUG
        do {
            try await api.bootstrapDemo(on: date, accessToken: accessToken)
        } catch ScheduleAPIError.server(let status, _, _, _) where status == 404 {
            // The backend owns whether development seed data is enabled.
        }
        #endif
        let calendarDTOs = try await api.calendars(accessToken: accessToken)
        let calendars = calendarDTOs.map(\.scheduleCalendar)
        let calendarsByID = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0) })
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -30, to: date) ?? date
        let to = calendar.date(byAdding: .day, value: 60, to: date) ?? date
        let todos = try await api.todos(from: from, to: to, accessToken: accessToken)
        let schedules = try todos.map { dto in
            guard let calendar = calendarsByID[dto.calendarId] else {
                throw ScheduleAPIError.incompatibleValue(dto.calendarId)
            }
            return try ScheduleDetail(dto: dto, calendar: calendar)
        }
        return ScheduleSnapshot(schedules: schedules, calendars: calendars)
    }

    /// Fetches just an additional date range (no demo-seed bootstrap), for
    /// extending an already-loaded window when the user navigates outside it.
    func loadRange(from: Date, to: Date) async throws -> [ScheduleDetail] {
        let accessToken = try await accessToken()
        let calendarDTOs = try await api.calendars(accessToken: accessToken)
        let calendarsByID = Dictionary(
            uniqueKeysWithValues: calendarDTOs.map { ($0.id, $0.scheduleCalendar) }
        )
        let todos = try await api.todos(from: from, to: to, accessToken: accessToken)
        return try todos.map { dto in
            guard let calendar = calendarsByID[dto.calendarId] else {
                throw ScheduleAPIError.incompatibleValue(dto.calendarId)
            }
            return try ScheduleDetail(dto: dto, calendar: calendar)
        }
    }

    func create(_ schedule: ScheduleDetail) async throws -> ScheduleDetail {
        let accessToken = try await accessToken()
        let dto = try await api.create(
            TodoCreateRequestDTO(schedule: schedule),
            idempotencyKey: schedule.id,
            accessToken: accessToken
        )
        return try ScheduleDetail(dto: dto, calendar: schedule.calendar)
    }

    func update(_ schedule: ScheduleDetail) async throws -> ScheduleDetail {
        let accessToken = try await accessToken()
        let dto = try await api.update(schedule, accessToken: accessToken)
        return try ScheduleDetail(dto: dto, calendar: schedule.calendar)
    }

    func delete(_ schedule: ScheduleDetail) async throws {
        try await delete(id: schedule.id, version: schedule.version)
    }

    /// Used by the outbox replay path, which only has an id/version pair
    /// (from a queued `.delete` operation), not a full `ScheduleDetail`.
    func delete(id: UUID, version: Int) async throws {
        let accessToken = try await accessToken()
        try await api.delete(id: id, version: version, accessToken: accessToken)
    }

    func reschedule(
        _ schedule: ScheduleDetail,
        baseVersion: Int
    ) async throws -> (original: ScheduleDetail, replacement: ScheduleDetail) {
        let accessToken = try await accessToken()
        let result = try await api.reschedule(
            id: schedule.id,
            input: TodoRescheduleRequestDTO(schedule: schedule, baseVersion: baseVersion),
            idempotencyKey: UUID(),
            accessToken: accessToken
        )
        return (
            try ScheduleDetail(dto: result.original, calendar: schedule.calendar),
            try ScheduleDetail(dto: result.replacement, calendar: schedule.calendar)
        )
    }

    func sync(cursor: String?) async throws -> SyncResponseDTO {
        try await api.sync(cursor: cursor, accessToken: accessToken())
    }

    func search(query: String) async throws -> [TodoResponseDTO] {
        try await api.search(query: query, accessToken: accessToken()).items
    }

    func createRule(_ schedule: ScheduleDetail) async throws {
        try await api.createRule(ScheduleRuleRequestDTO(schedule: schedule), accessToken: accessToken())
    }

    func deleteRule(id: String) async throws {
        try await api.deleteRule(id: id, localDate: APIDate.day(.now), accessToken: accessToken())
    }

    func googleCalendarStart() async throws -> URL {
        let response = try await api.googleCalendarStart(accessToken: accessToken())
        guard let url = URL(string: response.authorizationUrl) else {
            throw ScheduleAPIError.invalidResponse
        }
        return url
    }

    func googleCalendarStatus() async throws -> GoogleCalendarStatusResponseDTO {
        try await api.googleCalendarStatus(accessToken: accessToken())
    }

    func googleCalendarDisconnect() async throws {
        _ = try await api.googleCalendarDisconnect(accessToken: accessToken())
    }

    func loadCategories() async throws -> [ScheduleUserCategory] {
        try await api.categories(accessToken: accessToken()).items
    }

    func replaceCategories(_ categories: [ScheduleUserCategory]) async throws -> [ScheduleUserCategory] {
        try await api.replaceCategories(categories, accessToken: accessToken()).items
    }

    func agentKeyConnected() async throws -> Bool {
        try await api.agentKeyStatus(accessToken: accessToken()).connected
    }

    func saveAgentKey(_ apiKey: String) async throws {
        _ = try await api.saveAgentKey(apiKey, accessToken: accessToken())
    }

    func deleteAgentKey() async throws {
        _ = try await api.deleteAgentKey(accessToken: accessToken())
    }

    /// Best-effort -- called right after a successful Apple sign-in
    /// (signInWithIdToken already completed by the time this runs), so a
    /// failure here must never surface as a sign-in failure. Errors are
    /// left for the caller to swallow/log; this repository layer doesn't
    /// decide UI behavior.
    func exchangeAppleAuthCode(_ authorizationCode: String) async throws {
        _ = try await api.exchangeAppleAuthCode(authorizationCode, accessToken: accessToken())
    }

    func deleteAccount() async throws {
        _ = try await api.deleteAccount(accessToken: accessToken())
    }

    func agentModels() async throws -> [AgentModelDTO] {
        try await api.agentModels(accessToken: accessToken())
    }

    func agentUsage(days: Int = 30) async throws -> AgentUsageResponseDTO {
        try await api.agentUsage(days: days, accessToken: accessToken())
    }

    func agentCloudChat(
        message: String,
        history: [AgentChatTurnDTO],
        model: String?,
        onDelta: @escaping @MainActor (String) -> Void,
        onToolCallStarted: @escaping @MainActor (String) -> Void = { _ in },
        onToolCallFinished: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> AgentCloudChatResult {
        try await api.agentCloudChat(
            message: message,
            history: history,
            model: model,
            accessToken: accessToken(),
            onDelta: onDelta,
            onToolCallStarted: onToolCallStarted,
            onToolCallFinished: onToolCallFinished
        )
    }

    func review(date: String) async throws -> ReviewDTO? {
        try await api.review(date: date, accessToken: accessToken())
    }

    func putReview(date: String, reflection: String) async throws -> ReviewDTO {
        try await api.putReview(date: date, reflection: reflection, accessToken: accessToken())
    }

    private func accessToken() async throws -> String {
        guard auth.auth.currentSession != nil else { throw ScheduleAPIError.notAuthenticated }
        return try await auth.auth.session.accessToken
    }
}

struct MemdoConfiguration {
    let projectURL: URL
    let publishableKey: String

    static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        let rawURL = environment["SUPABASE_URL"] ?? bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let key = environment["SUPABASE_PUBLISHABLE_KEY"]
            ?? bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
        guard let rawURL, !rawURL.contains("$("), let projectURL = URL(string: rawURL),
              let key, !key.isEmpty, !key.contains("$(") else {
            throw ScheduleAPIError.missingConfiguration
        }
        return Self(projectURL: projectURL, publishableKey: key)
    }
}

extension ScheduleDetail {
    init(dto: TodoResponseDTO, calendar: ScheduleCalendar) throws {
        guard let id = UUID(uuidString: dto.id),
              let scheduledDate = APIDate.parseDay(dto.scheduledDate),
              let kind = ScheduleKind(rawValue: dto.entryKind),
              let status = ScheduleStatus(rawValue: dto.status),
              let timeBucket = ScheduleTimeBucket(rawValue: dto.timeBucket) else {
            throw ScheduleAPIError.incompatibleValue("todo")
        }

        self.id = id
        self.scheduledDate = scheduledDate
        startAt = try dto.startAt.map(APIDate.parseInstant)
        endAt = try dto.endAt.map(APIDate.parseInstant)
        dueAt = try dto.dueAt.map(APIDate.parseInstant)
        title = dto.title
        self.status = status
        locationValue = try dto.location.map { location in
            let provider = try location.provider.map {
                guard let value = ScheduleLocation.Provider(rawValue: $0) else {
                    throw ScheduleAPIError.incompatibleValue($0)
                }
                return value
            }
            return ScheduleLocation(
                name: location.name,
                address: location.address,
                latitude: location.latitude,
                longitude: location.longitude,
                provider: provider,
                providerID: location.providerId
            )
        }
        memo = dto.note ?? ""
        reminderOffsetMinutes = dto.reminderOffsetMinutes
        repeatRule = .never
        self.kind = kind
        self.calendar = calendar
        isAllDay = dto.isAllDay
        self.timeBucket = timeBucket
        sortOrder = dto.sortOrder
        version = dto.version
        scheduleRuleId = dto.scheduleRuleId
        categoryId = dto.categoryId.flatMap(UUID.init(uuidString:))
        color = dto.color.flatMap(ScheduleColor.init(rawValue:))
        emoji = dto.emoji
        estimatedMinutes = dto.estimatedMinutes
        meetingURLString = dto.meetingUrl.flatMap { $0.isEmpty ? nil : $0 }
        isVirtual = dto.isVirtual ?? false
    }
}

private struct ErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let code: String
        let message: String
        let requestId: String?
    }

    let error: APIError
}

private enum APIDate {
    // ISO8601DateFormatter is expensive to create; formatting/parsing on a shared
    // read-only instance is thread-safe, so cache one per format policy.
    nonisolated(unsafe) private static let standardFormatter = ISO8601DateFormatter()
    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()

    static func day(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func instant(_ date: Date) -> String {
        standardFormatter.string(from: date)
    }

    static func parseDay(_ value: String) -> Date? {
        let numbers = value.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2]))
    }

    static func parseInstant(_ value: String) throws -> Date {
        if let date = fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value) {
            return date
        }
        throw ScheduleAPIError.incompatibleValue(value)
    }
}
