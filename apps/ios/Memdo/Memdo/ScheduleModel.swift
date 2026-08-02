import Foundation
import Observation

enum ScheduleKind: String, CaseIterable, Identifiable {
    case event = "시간 일정"
    case task = "할 일"

    var id: String { rawValue }
}

struct ScheduleCalendar: Identifiable, Equatable, Hashable {
    enum Provider: String {
        case memdo = "내 일정"
        case google = "Google Calendar"

        var systemImage: String {
            switch self {
            case .memdo: "calendar"
            case .google: "calendar.badge.checkmark"
            }
        }
    }

    let id: String
    let title: String
    let provider: Provider

    static let personal = ScheduleCalendar(id: "memdo-personal", title: "개인", provider: .memdo)
    static let work = ScheduleCalendar(id: "memdo-work", title: "업무", provider: .memdo)
    static let google = ScheduleCalendar(id: "google-primary", title: "Google · 기본", provider: .google)
    static let defaults = [personal, work, google]
}

enum ScheduleRepeatRule: String, CaseIterable, Identifiable {
    case never = "반복 안 함"
    case daily = "매일"
    case weekdays = "평일마다"
    case weekly = "매주"
    case biweekly = "2주마다"
    case monthly = "매월"
    case yearly = "매년"

    var id: String { rawValue }
}

struct ScheduleDetail: Identifiable, Equatable {
    let id: UUID
    var startAt: Date
    var endAt: Date
    var dueAt: Date?
    var title: String
    var isDone: Bool
    var location: String
    var memo: String
    var reminder: String
    var repeatRule: ScheduleRepeatRule
    var kind: ScheduleKind
    var calendar: ScheduleCalendar
    var isAllDay: Bool

    init(
        id: UUID = UUID(),
        day: Int,
        time: String,
        title: String,
        isDone: Bool = false,
        location: String = "",
        memo: String = "",
        reminder: String = "30분 전",
        repeatRule: ScheduleRepeatRule = .never,
        kind: ScheduleKind = .event,
        calendar: ScheduleCalendar = .personal,
        isAllDay: Bool = false,
        durationMinutes: Int = 60,
        dueDay: Int? = nil,
        dueTime: String = "18:00"
    ) {
        self.id = id
        let startAt = Self.date(day: day, time: time)
        self.startAt = startAt
        self.endAt = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startAt) ?? startAt
        self.dueAt = dueDay.map { Self.date(day: $0, time: dueTime) }
        self.title = title
        self.isDone = isDone
        self.location = location
        self.memo = memo
        self.reminder = reminder
        self.repeatRule = repeatRule
        self.kind = kind
        self.calendar = calendar
        self.isAllDay = isAllDay
    }

    var source: String { calendar.provider.rawValue }
    var isExternal: Bool { calendar.provider == .google }
    var day: Int { Calendar.current.component(.day, from: startAt) }
    var time: String { Self.clockText(startAt) }
    var displayTime: String {
        guard !isAllDay else { return "종일" }
        return "\(Self.clockText(startAt))–\(Self.clockText(endAt))"
    }
    var startTimeText: String { Self.clockText(startAt) }
    var endTimeText: String { Self.clockText(endAt) }
    var dueTimeText: String? { dueAt.map(Self.clockText) }
    var dateText: String {
        let components = Calendar.current.dateComponents([.month, .day], from: startAt)
        return "\(components.month ?? 0)월 \(components.day ?? 0)일"
    }
    var timeSortKey: Date { isAllDay ? Calendar.current.startOfDay(for: startAt) : startAt }
    var kindLabel: String { kind.rawValue }
    var isTimeRangeValid: Bool { endAt > startAt }

    private static func date(day: Int, time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: day,
                hour: parts.first ?? 9,
                minute: parts.count > 1 ? parts[1] : 0
            )
        ) ?? .now
    }

    private static func clockText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

@Observable
final class ScheduleStore {
    var schedules: [ScheduleDetail]
    var calendars: [ScheduleCalendar]

    init(
        schedules: [ScheduleDetail] = ScheduleDetail.samples,
        calendars: [ScheduleCalendar] = ScheduleCalendar.defaults
    ) {
        self.schedules = schedules
        self.calendars = calendars
    }

    func items(for day: Int) -> [ScheduleDetail] {
        schedules
            .filter { $0.day == day }
            .sorted { $0.timeSortKey < $1.timeSortKey }
    }

    func items(for date: Date) -> [ScheduleDetail] {
        schedules
            .filter { Calendar.current.isDate($0.startAt, inSameDayAs: date) }
            .sorted { $0.timeSortKey < $1.timeSortKey }
    }

    func save(_ schedule: ScheduleDetail) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
    }

    func toggleDone(id: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == id }),
              schedules[index].kind == .task else { return }
        schedules[index].isDone.toggle()
    }

    func move(id: UUID, to date: Date) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        let calendar = Calendar.current
        let oldStart = schedules[index].startAt
        let duration = schedules[index].endAt.timeIntervalSince(oldStart)
        let time = calendar.dateComponents([.hour, .minute, .second], from: oldStart)
        guard let newStart = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: date
        ) else { return }

        schedules[index].startAt = newStart
        schedules[index].endAt = newStart.addingTimeInterval(duration)
        if let dueAt = schedules[index].dueAt, calendar.isDate(dueAt, inSameDayAs: oldStart) {
            let dueTime = calendar.dateComponents([.hour, .minute, .second], from: dueAt)
            schedules[index].dueAt = calendar.date(
                bySettingHour: dueTime.hour ?? 0,
                minute: dueTime.minute ?? 0,
                second: dueTime.second ?? 0,
                of: date
            )
        }
        assert(calendar.isDate(schedules[index].startAt, inSameDayAs: date))
    }

    func delete(id: UUID) {
        schedules.removeAll { $0.id == id }
    }

    @discardableResult
    func addCalendar(named name: String) -> ScheduleCalendar? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let calendar = ScheduleCalendar(id: UUID().uuidString, title: title, provider: .memdo)
        calendars.append(calendar)
        return calendar
    }
}

extension ScheduleDetail {
    static let samples = [
        ScheduleDetail(day: 31, time: "10:00", title: "앱 기획 문서 다듬기", memo: "기능 우선순위와 화면 흐름 정리", kind: .task, calendar: .work, durationMinutes: 90, dueDay: 31, dueTime: "12:00"),
        ScheduleDetail(day: 31, time: "14:30", title: "디자인 시안 확인", location: "온라인 미팅", calendar: .google, durationMinutes: 60),
        ScheduleDetail(day: 31, time: "19:00", title: "30분 산책", location: "한강 공원", kind: .task, durationMinutes: 30),
        ScheduleDetail(day: 31, time: "20:00", title: "영어 단어 복습", kind: .task, durationMinutes: 30),
        ScheduleDetail(day: 31, time: "20:30", title: "주간 메모 정리", kind: .task, calendar: .google, durationMinutes: 30),
        ScheduleDetail(day: 31, time: "21:00", title: "친구에게 연락", kind: .task, durationMinutes: 30),
        ScheduleDetail(day: 31, time: "21:30", title: "오늘 요약", kind: .event, durationMinutes: 15),
        ScheduleDetail(day: 30, time: "11:00", title: "프로토타입 흐름 점검", isDone: true, memo: "날짜 선택과 상세 진입 흐름 확인", kind: .task),
        ScheduleDetail(day: 30, time: "16:30", title: "문서 구조 정리", isDone: true, kind: .task),
        ScheduleDetail(day: 29, time: "19:00", title: "저녁 산책", isDone: true, location: "동네 공원", kind: .task, durationMinutes: 30),
        ScheduleDetail(day: 28, time: "18:30", title: "주간 운동 계획", kind: .task, durationMinutes: 30),
        ScheduleDetail(day: 25, time: "20:00", title: "회고 메모 정리", kind: .task, durationMinutes: 30),
        ScheduleDetail(day: 24, time: "11:00", title: "위젯 디자인 리뷰", isDone: true, memo: "잠금화면 위젯 정보 밀도 확인", kind: .task),
        ScheduleDetail(day: 18, time: "16:00", title: "디자인 시스템 정리", isDone: true, kind: .task),
        ScheduleDetail(day: 8, time: "19:30", title: "저녁 산책", isDone: true, location: "동네 공원", kind: .task, durationMinutes: 30)
    ]
}
