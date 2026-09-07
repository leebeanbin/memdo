import Foundation

/// Shared between the Memdo app and the MemdoWidget extension.
/// This file must belong to BOTH targets so the App Group storage keys and the
/// widget snapshot wire format have a single source of truth.
enum MemdoWidgetStorage {
    static let suiteName = "group.com.memdo.ios"
    static let snapshotKey = "today-schedule-snapshot"
    static let hideContentKey = "hide-widget-content"
}

struct MemdoWidgetSnapshot: Codable {
    let updatedAt: Date
    let days: [MemdoWidgetDay]

    func day(for date: Date) -> MemdoWidgetDay {
        days.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
            ?? MemdoWidgetDay(date: Calendar.current.startOfDay(for: date), completedCount: 0, items: [])
    }

    func nextDay(after date: Date) -> MemdoWidgetDay? {
        days.first {
            $0.date > Calendar.current.startOfDay(for: date) && !$0.items.isEmpty
        }
    }

    static func empty(at date: Date) -> Self {
        Self(updatedAt: date, days: [])
    }

    static func sample(at date: Date) -> Self {
        let calendar = Calendar.current
        func day(_ offset: Int, _ items: [MemdoWidgetItem], completed: Int = 0) -> MemdoWidgetDay {
            MemdoWidgetDay(
                date: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date,
                completedCount: completed,
                items: items
            )
        }
        func item(_ time: String, _ title: String, _ kind: String = "event", _ color: String? = nil) -> MemdoWidgetItem {
            MemdoWidgetItem(id: UUID(), time: time, title: title, kind: kind, color: color)
        }
        return Self(updatedAt: date, days: [
            day(0, [
                item("10:00", "기획 문서 다듬기", "event", "indigo"),
                item("14:30", "디자인 시안 확인", "event", "sky"),
                item("19:00", "30분 산책", "task", "sage"),
                item("저녁", "하루 정리", "task")
            ], completed: 2),
            day(1, [item("09:30", "주간 계획 정리", "task", "amber")]),
            day(3, [item("15:00", "프로젝트 미팅", "event", "coral")]),
            day(5, [item("오전", "장보기", "task"), item("18:00", "운동", "task", "sage")]),
            day(8, [item("11:00", "제품 리뷰", "event", "violet")])
        ])
    }
}

struct MemdoWidgetDay: Codable, Hashable {
    let date: Date
    let completedCount: Int
    let items: [MemdoWidgetItem]

    var remainingCount: Int { items.count }
    var totalCount: Int { completedCount + remainingCount }
}

struct MemdoWidgetItem: Codable, Hashable {
    let id: UUID
    let time: String
    let title: String
    let kind: String
    let color: String?

    var systemImage: String { kind == "task" ? "checkmark.square" : "clock" }

    init(id: UUID, time: String, title: String, kind: String, color: String? = nil) {
        self.id = id
        self.time = time
        self.title = title
        self.kind = kind
        self.color = color
    }
}
