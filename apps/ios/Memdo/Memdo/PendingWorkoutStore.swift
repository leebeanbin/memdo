import Foundation

/// Shared between the Memdo app and the MemdoShare extension via App Group.
/// MemdoShare queues workouts here; the main app drains and saves them on foreground.
struct PendingWorkout: Codable, Sendable {
    var id: UUID = UUID()
    var activityType: String   // WorkoutActivityType.rawValue
    var startedAt: Date
    var endedAt: Date
    var notes: String
    var sourceText: String?    // raw text from share sheet (URL, summary etc.)
}

enum PendingWorkoutStore {
    private static let key = "memdo.pending-workouts"

    static func enqueue(_ workout: PendingWorkout) {
        var list = load()
        list.append(workout)
        persist(list)
    }

    /// Removes and returns the next pending workout, one at a time.
    /// Safer than drain(): if the app crashes after dequeue but before save,
    /// only that one item is lost rather than the entire queue.
    static func dequeueOne() -> PendingWorkout? {
        var list = load()
        guard !list.isEmpty else { return nil }
        let item = list.removeFirst()
        persist(list)
        return item
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.memdo.ios") }

    private static func load() -> [PendingWorkout] {
        guard let data = defaults?.data(forKey: key),
              let list = try? JSONDecoder().decode([PendingWorkout].self, from: data)
        else { return [] }
        return list
    }

    private static func persist(_ list: [PendingWorkout]) {
        defaults?.set(try? JSONEncoder().encode(list), forKey: key)
    }
}
