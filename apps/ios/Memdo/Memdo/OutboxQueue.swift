import Foundation
import Network

/// A write that failed because the request never reached the server (see
/// `ScheduleAPIError.offline`), queued for replay once connectivity returns.
/// Create/reschedule reuse the idempotency keys already sent the first time
/// (see ScheduleRepository), and update/delete reuse the optimistic-lock
/// version already captured -- so replaying is safe without any new
/// server-side support.
enum OutboxOperation: Codable {
    case create(ScheduleDetail)
    case update(ScheduleDetail)
    case delete(id: UUID, version: Int)
    case reschedule(original: ScheduleDetail, moved: ScheduleDetail, baseVersion: Int)
    /// A virtual (never-materialized) recurring occurrence whose materialize
    /// step itself never reached the server, so there's no real row/version
    /// yet to target -- replay must redo the materialize before acting.
    case materializeThenDelete(ScheduleDetail)
    case materializeThenReschedule(original: ScheduleDetail, moved: ScheduleDetail)
}

struct OutboxEntry: Codable {
    let scheduleID: UUID
    var operation: OutboxOperation
    let enqueuedAt: Date
}

/// Durable, disk-backed queue of writes that failed offline. Keyed by
/// schedule id rather than a plain list: editing the same item several times
/// while offline collapses to one replay of the latest intent, matching how
/// `ScheduleStore.pendingWriteIDs` already treats one in-flight write per id.
actor OutboxStore {
    private let fileURL: URL
    private var entries: [UUID: OutboxEntry] = [:]
    private var loaded = false

    init(fileURL: URL = OutboxStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("outbox.json")
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([UUID: OutboxEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// A blind overwrite here is only correct when the *kind* of the pending
    /// operation doesn't change (update-over-update, delete-over-update,
    /// etc. -- the case this type's own doc comment above describes). It is
    /// wrong when a `.create` is still pending: that row was never actually
    /// materialized server-side, so replacing it with `.update`/`.reschedule`
    /// (which target an existing row by id) 404s on replay and the item is
    /// silently dropped, and replacing it with `.delete` would try to delete
    /// something that was never created. Founder-dogfooding fix -- this is
    /// what let an offline-created, then offline-edited-again schedule
    /// vanish on reconnect.
    func enqueue(_ operation: OutboxOperation, scheduleID: UUID) {
        ensureLoaded()
        if case .create = entries[scheduleID]?.operation {
            switch operation {
            case .update(let detail):
                entries[scheduleID] = OutboxEntry(scheduleID: scheduleID, operation: .create(detail), enqueuedAt: .now)
            case .reschedule(_, let moved, _):
                entries[scheduleID] = OutboxEntry(scheduleID: scheduleID, operation: .create(moved), enqueuedAt: .now)
            case .delete:
                // Nothing was ever created server-side -- cancel the
                // pending create rather than queuing a delete for a row
                // that doesn't exist.
                entries.removeValue(forKey: scheduleID)
            case .create, .materializeThenDelete, .materializeThenReschedule:
                // A second .create for the same id, or a virtual-occurrence
                // operation, shouldn't arise while a plain .create is
                // already pending -- fall back to today's overwrite rather
                // than guessing.
                entries[scheduleID] = OutboxEntry(scheduleID: scheduleID, operation: operation, enqueuedAt: .now)
            }
        } else {
            entries[scheduleID] = OutboxEntry(scheduleID: scheduleID, operation: operation, enqueuedAt: .now)
        }
        persist()
    }

    func remove(_ scheduleID: UUID) {
        ensureLoaded()
        guard entries.removeValue(forKey: scheduleID) != nil else { return }
        persist()
    }

    /// Called on sign-out/account switch (`ScheduleStore.reset()`) -- this
    /// store has no user scoping of its own, so without this a different
    /// user signing in on the same device would have the previous user's
    /// queued writes replayed under their access token (founder-dogfooding
    /// fix: cross-account data leak/loss).
    func removeAll() {
        ensureLoaded()
        guard !entries.isEmpty else { return }
        entries.removeAll()
        persist()
    }

    /// Oldest-first, so items queued earlier (e.g. a create) replay before
    /// later ones that might depend on them existing.
    func all() -> [OutboxEntry] {
        ensureLoaded()
        return entries.values.sorted { $0.enqueuedAt < $1.enqueuedAt }
    }
}

/// Watches for connectivity and calls back on every transition to a usable
/// path -- including the very first callback at app launch, which doubles as
/// the "drain whatever was queued from a previous, killed-while-offline
/// session" trigger without needing a separate launch hook.
final class NetworkMonitor {
    private let monitor = NWPathMonitor()

    init(onReconnect: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied { onReconnect() }
        }
        monitor.start(queue: DispatchQueue(label: "com.memdo.network-monitor"))
    }

    deinit {
        monitor.cancel()
    }
}
