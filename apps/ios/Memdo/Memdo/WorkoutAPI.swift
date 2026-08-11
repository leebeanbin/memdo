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
}

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

    func accessToken() async throws -> String {
        try await auth.auth.session.accessToken
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

    // MARK: Storage

    /// 이미지 Data → Supabase Storage 업로드 → public URL 반환
    func uploadImage(_ data: Data, path: String) async throws -> String {
        let options = FileOptions(contentType: "image/jpeg", upsert: true)
        _ = try await auth.storage.from(Self.mediaBucket).upload(path: path, file: data, options: options)
        let url = try auth.storage.from(Self.mediaBucket).getPublicURL(path: path)
        return url.absoluteString
    }

    func routeImagePath(workoutID: UUID) -> String { "\(workoutID.uuidString.lowercased())/route.jpg" }
    func photoPath(workoutID: UUID)      -> String { "\(workoutID.uuidString.lowercased())/photo.jpg" }
}
