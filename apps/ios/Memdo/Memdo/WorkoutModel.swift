import Foundation
import HealthKit
import Observation

// MARK: - Activity Type

enum WorkoutActivityType: String, CaseIterable, Identifiable, Codable {
    case running, cycling, swimming
    case strengthTraining = "strength_training"
    case yoga, hiit, walking, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .running:          "러닝"
        case .cycling:          "사이클"
        case .swimming:         "수영"
        case .strengthTraining: "근력 운동"
        case .yoga:             "요가"
        case .hiit:             "HIIT"
        case .walking:          "걷기"
        case .other:            "기타 운동"
        }
    }

    var systemImage: String {
        switch self {
        case .running:          "figure.run"
        case .cycling:          "figure.outdoor.cycle"
        case .swimming:         "figure.pool.swim"
        case .strengthTraining: "dumbbell"
        case .yoga:             "figure.yoga"
        case .hiit:             "figure.highintensity.intervaltraining"
        case .walking:          "figure.walk"
        case .other:            "figure.mixed.cardio"
        }
    }

    init(hkType: HKWorkoutActivityType) {
        switch hkType {
        case .running:                                  self = .running
        case .cycling, .handCycling:                    self = .cycling
        case .swimming:                                 self = .swimming
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:               self = .strengthTraining
        case .yoga:                                     self = .yoga
        case .highIntensityIntervalTraining:            self = .hiit
        case .walking:                                  self = .walking
        default:                                        self = .other
        }
    }
}

// MARK: - Exercise Set (헬스장 세트 단위)

struct ExerciseSet: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sets: Int
    var reps: Int?
    var weightKg: Double?
    var durationSeconds: Int?

    var summary: String {
        var parts = ["\(sets)세트"]
        if let reps { parts.append("\(reps)회") }
        if let kg = weightKg { parts.append(String(format: "%.1fkg", kg)) }
        if let sec = durationSeconds {
            parts.append(sec >= 60 ? "\(sec / 60)분" : "\(sec)초")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Workout Log

struct WorkoutLog: Identifiable, Codable, Equatable {
    enum Source: String, Codable { case healthkit, manual }

    var id: UUID
    var hkUUID: String?         // HealthKit UUID — dedup 기준
    var source: Source
    var activityType: WorkoutActivityType
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Int
    var distanceMeters: Double?
    var calories: Double?
    var avgHeartRate: Double?
    var locationName: String?   // 수동 입력 ("강남 헬스장")
    var routeImageURL: String?  // GPS 경로 자동 렌더
    var photoURL: String?       // 사용자 첨부 사진 (Nike RC 캡처 등)
    var exercises: [ExerciseSet]?
    var notes: String

    var scheduledDate: Date { Calendar.current.startOfDay(for: startedAt) }

    var durationFormatted: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }

    var distanceFormatted: String? {
        guard let m = distanceMeters, m > 0 else { return nil }
        return String(format: "%.2fkm", m / 1000)
    }

    var paceFormatted: String? {
        guard let m = distanceMeters, m > 100, durationSeconds > 0,
              activityType == .running || activityType == .walking else { return nil }
        let secsPerKm = Double(durationSeconds) / (m / 1000)
        return String(format: "%d'%02d\"", Int(secsPerKm) / 60, Int(secsPerKm) % 60)
    }

    init(
        id: UUID = UUID(), hkUUID: String? = nil, source: Source = .manual,
        activityType: WorkoutActivityType, startedAt: Date, endedAt: Date,
        durationSeconds: Int, distanceMeters: Double? = nil, calories: Double? = nil,
        avgHeartRate: Double? = nil, locationName: String? = nil,
        routeImageURL: String? = nil, photoURL: String? = nil,
        exercises: [ExerciseSet]? = nil, notes: String = ""
    ) {
        self.id = id; self.hkUUID = hkUUID; self.source = source
        self.activityType = activityType; self.startedAt = startedAt
        self.endedAt = endedAt; self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters; self.calories = calories
        self.avgHeartRate = avgHeartRate; self.locationName = locationName
        self.routeImageURL = routeImageURL; self.photoURL = photoURL
        self.exercises = exercises; self.notes = notes
    }
}

// MARK: - Workout Store

@MainActor
@Observable
final class WorkoutStore {
    private(set) var workouts: [WorkoutLog] = []
    private(set) var isSyncing = false
    private(set) var lastSyncError: String?

    private let repository: WorkoutRepository?
    let importer: HealthKitImporter

    init(repository: WorkoutRepository? = nil) {
        self.repository = repository
        self.importer = HealthKitImporter()
    }

    func workouts(on date: Date) -> [WorkoutLog] {
        let target = Calendar.current.startOfDay(for: date)
        return workouts
            .filter { Calendar.current.startOfDay(for: $0.startedAt) == target }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func hasWorkouts(on date: Date) -> Bool { !workouts(on: date).isEmpty }

    func load() async {
        guard let repository else { return }
        do {
            let cal = Calendar.current
            let from = cal.date(byAdding: .day, value: -90, to: .now) ?? .now
            let to   = cal.date(byAdding: .day, value: 7,   to: .now) ?? .now
            workouts = try await repository.load(from: from, to: to)
        } catch { lastSyncError = error.localizedDescription }
    }

    // HealthKit에서 새 운동 가져오기 → (있으면) 경로 이미지 업로드 → 백엔드 저장
    func syncHealthKit() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard await importer.requestAuthorization() else { return }

        let known = Set(workouts.compactMap(\.hkUUID))
        let newLogs = await importer.fetchNewWorkouts(excluding: known)
        guard !newLogs.isEmpty else { return }

        for var log in newLogs {
            // 경로 이미지 렌더 (GPS 운동만)
            if let hkUUID = log.hkUUID,
               let hkWorkout = await importer.cachedWorkout(for: hkUUID),
               let imageData = await importer.renderRouteImage(for: hkWorkout) {
                if let repository {
                    let path = await repository.routeImagePath(workoutID: log.id)
                    log.routeImageURL = try? await repository.uploadImage(imageData, path: path)
                }
            }
            if let repository,
               let token = try? await repository.accessToken(),
               let saved = try? await repository.create(log, accessToken: token) {
                upsertLocally(saved)
            } else {
                upsertLocally(log)  // 백엔드 없을 때 로컬만
            }
        }
    }

    func save(_ workout: WorkoutLog) {
        Task {
            guard let repository,
                  let token = try? await repository.accessToken(),
                  let saved = try? await repository.create(workout, accessToken: token)
            else { upsertLocally(workout); return }
            upsertLocally(saved)
        }
    }

    // 노트/장소/세트 편집 — details 테이블만 업데이트
    func update(_ workout: WorkoutLog) {
        Task {
            guard let repository,
                  let token = try? await repository.accessToken(),
                  let saved = try? await repository.updateDetails(workout, accessToken: token)
            else { upsertLocally(workout); return }
            upsertLocally(saved)
        }
    }

    // 유저가 명시적으로 요청할 때만 호출 — 저장하지 않고 목록만 반환
    func fetchPendingFromHealthKit() async -> [WorkoutLog] {
        guard await importer.requestAuthorization() else { return [] }
        let known = Set(workouts.compactMap(\.hkUUID))
        return await importer.fetchNewWorkouts(excluding: known)
    }

    func dismissSyncError() { lastSyncError = nil }
    func reset() { workouts = []; lastSyncError = nil }

    private func upsertLocally(_ workout: WorkoutLog) {
        if let i = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[i] = workout
        } else {
            workouts.append(workout)
            workouts.sort { $0.startedAt > $1.startedAt }
        }
    }
}
