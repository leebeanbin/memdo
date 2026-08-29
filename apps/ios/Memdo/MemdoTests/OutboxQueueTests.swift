import XCTest
@testable import Memdo

/// Founder-dogfooding fix: `OutboxStore.enqueue` used to blindly overwrite
/// the pending entry for an id, which silently destroyed an offline-created
/// schedule the moment it was edited again before reconnecting (the
/// overwriting `.update`/`.reschedule`/`.delete` targets a row that was
/// never actually created server-side, so replay 404s and the item is
/// dropped). These tests pin the merge behavior that replaced it.
final class OutboxQueueTests: XCTestCase {
    private let calendar = ScheduleCalendar(
        id: "test-calendar",
        title: "테스트",
        purpose: "personal",
        provider: .memdo
    )

    private func makeStore() -> OutboxStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-test-\(UUID().uuidString).json")
        return OutboxStore(fileURL: fileURL)
    }

    private func detail(id: UUID, title: String) -> ScheduleDetail {
        ScheduleDetail(id: id, scheduledDate: .now, title: title, kind: .task, calendar: calendar)
    }

    func testUpdateOverPendingCreateStaysACreateWithTheLatestDetail() async throws {
        let store = makeStore()
        let id = UUID()
        await store.enqueue(.create(detail(id: id, title: "첫 제목")), scheduleID: id)
        await store.enqueue(.update(detail(id: id, title: "수정된 제목")), scheduleID: id)

        let entries = await store.all()
        XCTAssertEqual(entries.count, 1)
        guard case .create(let stored) = entries.first?.operation else {
            return XCTFail("expected .create to survive an .update over a pending create")
        }
        XCTAssertEqual(stored.title, "수정된 제목")
    }

    func testRescheduleOverPendingCreateStaysACreateWithTheMovedDetail() async throws {
        let store = makeStore()
        let id = UUID()
        let original = detail(id: id, title: "원본")
        let moved = detail(id: id, title: "원본")
        await store.enqueue(.create(original), scheduleID: id)
        await store.enqueue(.reschedule(original: original, moved: moved, baseVersion: 1), scheduleID: id)

        let entries = await store.all()
        XCTAssertEqual(entries.count, 1)
        guard case .create(let stored) = entries.first?.operation else {
            return XCTFail("expected .create to survive a .reschedule over a pending create")
        }
        XCTAssertEqual(stored.id, moved.id)
    }

    func testDeleteOverPendingCreateCancelsItInsteadOfQueuingADelete() async throws {
        let store = makeStore()
        let id = UUID()
        await store.enqueue(.create(detail(id: id, title: "지워질 예정")), scheduleID: id)
        await store.enqueue(.delete(id: id, version: 1), scheduleID: id)

        let entries = await store.all()
        XCTAssertTrue(entries.isEmpty, "a create that never reached the server should be cancelled outright, not replaced with a delete")
    }

    func testUpdateOverPendingUpdateStillOverwritesNormally() async throws {
        let store = makeStore()
        let id = UUID()
        await store.enqueue(.update(detail(id: id, title: "첫 수정")), scheduleID: id)
        await store.enqueue(.update(detail(id: id, title: "두 번째 수정")), scheduleID: id)

        let entries = await store.all()
        XCTAssertEqual(entries.count, 1)
        guard case .update(let stored) = entries.first?.operation else {
            return XCTFail("expected the normal collapse-to-latest-intent behavior for non-create entries")
        }
        XCTAssertEqual(stored.title, "두 번째 수정")
    }

    func testRemoveAllClearsEveryEntry() async throws {
        let store = makeStore()
        let idA = UUID()
        let idB = UUID()
        await store.enqueue(.create(detail(id: idA, title: "A")), scheduleID: idA)
        await store.enqueue(.create(detail(id: idB, title: "B")), scheduleID: idB)
        let beforeCount = await store.all().count
        XCTAssertEqual(beforeCount, 2)

        await store.removeAll()

        let afterEntries = await store.all()
        XCTAssertTrue(afterEntries.isEmpty)
    }
}
