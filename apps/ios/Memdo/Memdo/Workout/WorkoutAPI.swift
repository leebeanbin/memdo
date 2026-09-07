import Foundation
import Supabase

// MARK: - Date Formatting

private enum WorkoutDate {
    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()

    static func instant(_ date: Date) -> String { iso.string(from: date) }

    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Create Request DTO (workout_logs + workout_log_details 동시)

struct WorkoutLogCreateRequestDTO: Encodable {
    let hkUuid: String?
    let source: String
    let activityType: String
    let startedAt: String
    let endedAt: String
    let durationSec: Int
    let distanceM: Double?
    let calories: Double?
    let avgHeartRate: Double?
    let routeImageUrl: String?
    let photoUrl: String?
    let scheduledDate: String
    // workout_log_details 영역
    let locationName: String?
    let notes: String
    let exercises: [ExerciseSetDTO]?

    struct ExerciseSetDTO: Encodable {
        let id: String; let name: String; let sets: Int
        let reps: Int?; let weightKg: Double?; let durationSeconds: Int?
    }

    init(log: WorkoutLog) {
        hkUuid        = log.hkUUID
        source        = log.source.rawValue
        activityType  = log.activityType.rawValue
        startedAt     = WorkoutDate.instant(log.startedAt)
        endedAt       = WorkoutDate.instant(log.endedAt)
        durationSec   = log.durationSeconds
        distanceM     = log.distanceMeters
        calories      = log.calories
        avgHeartRate  = log.avgHeartRate
        routeImageUrl = log.routeImageURL
        photoUrl      = log.photoURL
        scheduledDate = WorkoutDate.day(log.startedAt)
        locationName  = log.locationName
        notes         = log.notes
        exercises     = log.exercises?.map {
            ExerciseSetDTO(id: $0.id.uuidString, name: $0.name, sets: $0.sets,
                          reps: $0.reps, weightKg: $0.weightKg, durationSeconds: $0.durationSeconds)
        }
    }
}

// MARK: - Update Details Request DTO (workout_log_details 전용)

struct WorkoutLogUpdateDetailsRequestDTO: Encodable {
    let locationName: String?
    let notes: String
    let exercises: [WorkoutLogCreateRequestDTO.ExerciseSetDTO]?
}

// MARK: - Response DTO (workout_log_full 뷰 기준)

struct WorkoutLogResponseDTO: Decodable {
    let id: String
    let hkUuid: String?
    let source: String
    let activityType: String
    let startedAt: String
    let endedAt: String
    let durationSec: Int
    let distanceM: Double?
    let calories: Double?
    let avgHeartRate: Double?
    let routeImageUrl: String?
    let photoUrl: String?
    let scheduledDate: String
    let locationName: String?
    let notes: String
    let exercises: [ExerciseSetResponseDTO]?

    struct ExerciseSetResponseDTO: Decodable {
        let id: String; let name: String; let sets: Int
        let reps: Int?; let weightKg: Double?; let durationSeconds: Int?
    }

    func toWorkoutLog() -> WorkoutLog? {
        guard let id = UUID(uuidString: id) else { return nil }
        func parse(_ s: String) -> Date? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        guard let start = parse(startedAt), let end = parse(endedAt) else { return nil }
        return WorkoutLog(
            id: id, hkUUID: hkUuid,
            source: WorkoutLog.Source(rawValue: source) ?? .manual,
            activityType: WorkoutActivityType(rawValue: activityType) ?? .other,
            startedAt: start, endedAt: end, durationSeconds: durationSec,
            distanceMeters: distanceM, calories: calories, avgHeartRate: avgHeartRate,
            locationName: locationName.flatMap { $0.isEmpty ? nil : $0 },
            routeImageURL: routeImageUrl, photoURL: photoUrl,
            exercises: exercises?.map {
                ExerciseSet(id: UUID(uuidString: $0.id) ?? UUID(),
                           name: $0.name, sets: $0.sets, reps: $0.reps,
                           weightKg: $0.weightKg, durationSeconds: $0.durationSeconds)
            },
            notes: notes
        )
    }
}

private struct WorkoutLogListResponseDTO: Decodable {
    let items: [WorkoutLogResponseDTO]
}

// MARK: - MemdoAPIClient extension

extension MemdoAPIClient {
    func workoutLogs(from: Date, to: Date, accessToken: String) async throws -> [WorkoutLogResponseDTO] {
        let result: WorkoutLogListResponseDTO = try await send(
            path: "workout-logs",
            queryItems: [
                URLQueryItem(name: "from", value: WorkoutDate.day(from)),
                URLQueryItem(name: "to",   value: WorkoutDate.day(to))
            ],
            accessToken: accessToken
        )
        return result.items
    }

    func createWorkoutLog(
        _ input: WorkoutLogCreateRequestDTO,
        idempotencyKey: UUID,
        accessToken: String
    ) async throws -> WorkoutLogResponseDTO {
        try await send(
            path: "workout-logs",
            method: "POST",
            body: try JSONEncoder().encode(input),
            idempotencyKey: idempotencyKey,
            accessToken: accessToken
        )
    }

    func updateWorkoutLogDetails(
        id: UUID,
        _ input: WorkoutLogUpdateDetailsRequestDTO,
        accessToken: String
    ) async throws -> WorkoutLogResponseDTO {
        try await send(
            path: "workout-logs/\(id.uuidString.lowercased())/details",
            method: "PATCH",
            body: try JSONEncoder().encode(input),
            accessToken: accessToken
        )
    }

    func deleteWorkoutLog(id: UUID, accessToken: String) async throws {
        let _: WorkoutDeleteResponseDTO = try await send(
            path: "workout-logs/\(id.uuidString.lowercased())",
            method: "DELETE",
            accessToken: accessToken
        )
    }
}

private struct WorkoutDeleteResponseDTO: Decodable { let id: String }

// MARK: - Workout Repository

actor WorkoutRepository {
    private let auth: SupabaseClient
    private let api: MemdoAPIClient
    static let mediaBucket = "workout-media"

    init(configuration: MemdoConfiguration, auth: SupabaseClient) {
        self.auth = auth
        self.api  = MemdoAPIClient(projectURL: configuration.projectURL,
                                    publishableKey: configuration.publishableKey)
    }

    // fe12: the only repository without this guard -- a signed-out call
    // attempted a real network token refresh instead of failing fast, and
    // whatever opaque SDK error that produced overlapped with the try?
    // chains at every call site into a silent no-op. Mirrors
    // ScheduleRepository/PreferencesRepository's identical guard, including
    // reusing ScheduleAPIError.notAuthenticated (same shared error type,
    // not a new Workout-specific case).
    func accessToken() async throws -> String {
        guard auth.auth.currentSession != nil else { throw ScheduleAPIError.notAuthenticated }
        return try await auth.auth.session.accessToken
    }

    func load(from: Date, to: Date) async throws -> [WorkoutLog] {
        let token = try await accessToken()
        return try await api.workoutLogs(from: from, to: to, accessToken: token)
            .compactMap { $0.toWorkoutLog() }
    }

    func create(_ log: WorkoutLog, accessToken: String) async throws -> WorkoutLog {
        let response = try await api.createWorkoutLog(
            WorkoutLogCreateRequestDTO(log: log),
            idempotencyKey: log.id,
            accessToken: accessToken
        )
        return response.toWorkoutLog() ?? log
    }

    func updateDetails(_ log: WorkoutLog, accessToken: String) async throws -> WorkoutLog {
        let dto = WorkoutLogUpdateDetailsRequestDTO(
            locationName: log.locationName,
            notes: log.notes,
            exercises: log.exercises?.map {
                WorkoutLogCreateRequestDTO.ExerciseSetDTO(
                    id: $0.id.uuidString, name: $0.name, sets: $0.sets,
                    reps: $0.reps, weightKg: $0.weightKg, durationSeconds: $0.durationSeconds
                )
            }
        )
        let response = try await api.updateWorkoutLogDetails(id: log.id, dto, accessToken: accessToken)
        return response.toWorkoutLog() ?? log
    }

    func delete(id: UUID) async throws {
        let token = try await accessToken()
        try await api.deleteWorkoutLog(id: id, accessToken: token)
    }

    // bd26: /sync merges todos and workout_logs into one sync_seq-ordered
    // stream -- same shared endpoint ScheduleRepository.sync(cursor:) already
    // calls (MemdoAPIClient.sync is one method used by both repositories).
    // WorkoutStore.refresh() filters for entityType == "workout" and ignores
    // everything else in the page.
    func sync(cursor: String?) async throws -> SyncResponseDTO {
        try await api.sync(cursor: cursor, accessToken: accessToken())
    }

    // MARK: Storage

    /// 이미지 Data → Supabase Storage 업로드 → 오브젝트 경로 반환 (URL이 아님).
    /// fe11: workout-media 버킷은 private로 문서화되어 있는데 getPublicURL을
    /// 썼음 -- 버킷이 실제로 private이면 저장된 모든 routeImageURL/photoURL이
    /// 영구 깨진 링크였고, 실제로 public이면 GPS 경로가 접근 통제 없이 노출됐음.
    /// 이제 경로만 저장해두고, 표시 시점마다 signedURL(for:)로 단기 유효
    /// 서명 URL을 새로 발급받는다 -- 버킷의 실제 ACL이 무엇이든 안전.
    func uploadImage(_ data: Data, path: String) async throws -> String {
        let options = FileOptions(contentType: "image/jpeg", upsert: true)
        _ = try await auth.storage.from(Self.mediaBucket).upload(path, data: data, options: options)
        return path
    }

    /// 저장된 오브젝트 경로(routeImageURL/photoURL에 들어있는 값)로부터
    /// 표시용 서명 URL을 새로 발급. 매 표시 시점마다 호출 -- 서명 URL 자체를
    /// 저장하지 않는다 (만료됨).
    func signedURL(for path: String, expiresIn: Int = 3600) async throws -> URL {
        try await auth.storage.from(Self.mediaBucket).createSignedURL(path: path, expiresIn: expiresIn)
    }

    func routeImagePath(workoutID: UUID) -> String { "\(workoutID.uuidString.lowercased())/route.jpg" }
    func photoPath(workoutID: UUID)      -> String { "\(workoutID.uuidString.lowercased())/photo.jpg" }
}
