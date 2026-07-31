import Observation
import SwiftUI

struct ScheduleDetail: Identifiable, Equatable {
    let id: UUID
    var day: Int
    var time: String
    var title: String
    var source: String
    var isDone: Bool
    var location: String
    var memo: String
    var reminder: String
    var repeatRule: String

    init(
        id: UUID = UUID(),
        day: Int,
        time: String,
        title: String,
        source: String = "내 일정",
        isDone: Bool = false,
        location: String = "",
        memo: String = "",
        reminder: String = "30분 전",
        repeatRule: String = "반복 안 함"
    ) {
        self.id = id
        self.day = day
        self.time = time
        self.title = title
        self.source = source
        self.isDone = isDone
        self.location = location
        self.memo = memo
        self.reminder = reminder
        self.repeatRule = repeatRule
    }

    var isExternal: Bool { source.contains("Google") }
}

@Observable
final class ScheduleStore {
    var schedules: [ScheduleDetail]

    init(schedules: [ScheduleDetail] = ScheduleDetail.samples) {
        self.schedules = schedules
    }

    func items(for day: Int) -> [ScheduleDetail] {
        schedules
            .filter { $0.day == day }
            .sorted { $0.time < $1.time }
    }

    func save(_ schedule: ScheduleDetail) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
    }

    func toggleDone(id: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].isDone.toggle()
    }
}

extension ScheduleDetail {
    static let samples = [
        ScheduleDetail(day: 31, time: "10:00", title: "앱 기획 문서 다듬기", memo: "기능 우선순위와 화면 흐름 정리"),
        ScheduleDetail(day: 31, time: "14:30", title: "디자인 시안 확인", source: "Google Calendar", location: "온라인 미팅"),
        ScheduleDetail(day: 31, time: "19:00", title: "30분 산책", location: "한강 공원"),
        ScheduleDetail(day: 31, time: "20:00", title: "영어 단어 복습"),
        ScheduleDetail(day: 31, time: "20:30", title: "주간 메모 정리", source: "Google Calendar"),
        ScheduleDetail(day: 31, time: "21:00", title: "친구에게 연락"),
        ScheduleDetail(day: 31, time: "21:30", title: "오늘 요약"),
        ScheduleDetail(day: 30, time: "11:00", title: "프로토타입 흐름 점검", isDone: true, memo: "날짜 선택과 상세 진입 흐름 확인"),
        ScheduleDetail(day: 30, time: "16:30", title: "문서 구조 정리", isDone: true),
        ScheduleDetail(day: 29, time: "19:00", title: "저녁 산책", isDone: true, location: "동네 공원"),
        ScheduleDetail(day: 24, time: "11:00", title: "위젯 디자인 리뷰", isDone: true, memo: "잠금화면 위젯 정보 밀도 확인"),
        ScheduleDetail(day: 18, time: "16:00", title: "디자인 시스템 정리", isDone: true),
        ScheduleDetail(day: 8, time: "19:30", title: "저녁 산책", isDone: true, location: "동네 공원")
    ]
}

enum ScheduleRowContext {
    case timeline
    case dated
}

struct ScheduleRow: View {
    let schedule: ScheduleDetail
    let context: ScheduleRowContext
    let onOpen: () -> Void
    var onToggleDone: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    if context == .timeline {
                        Text(schedule.time)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(MemdoTheme.secondaryInk)
                            .frame(width: 48, alignment: .leading)
                    }

                    ScheduleSourceIcon(source: schedule.source)

                    VStack(alignment: .leading, spacing: 4) {
                        if context == .dated {
                            Text("7월 \(schedule.day)일 · \(schedule.time)")
                                .font(.caption)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                        Text(schedule.title)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .strikethrough(schedule.isDone)
                            .foregroundStyle(schedule.isDone ? MemdoTheme.secondaryInk : MemdoTheme.ink)
                        Text("\(schedule.isDone ? "완료 · " : "")\(schedule.source)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(MemdoTheme.secondaryInk)
                    }

                    Spacer(minLength: 0)

                    if onToggleDone == nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(MemdoTheme.secondaryInk)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onToggleDone {
                Button(action: onToggleDone) {
                    Image(systemName: schedule.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(schedule.isDone ? "완료 취소" : "완료로 표시")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct ScheduleSourceIcon: View {
    let source: String

    var body: some View {
        Image(systemName: source.contains("Google") ? "calendar" : "person.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(source.contains("Google") ? MemdoTheme.google : MemdoTheme.mine)
            .frame(width: 34, height: 34)
            .background(
                source.contains("Google") ? MemdoTheme.googleSoft : MemdoTheme.mineSoft,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

struct ScheduleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleDetail
    @State private var saved: ScheduleDetail
    @State private var isEditing = false

    let onSave: (ScheduleDetail) -> Void

    init(schedule: ScheduleDetail, onSave: @escaping (ScheduleDetail) -> Void) {
        _draft = State(initialValue: schedule)
        _saved = State(initialValue: schedule)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScheduleDetailHeader(schedule: draft)

                    HStack(spacing: 10) {
                        ScheduleStatusButton(isDone: $draft.isDone) {
                            saved = draft
                            onSave(draft)
                        }
                        .disabled(isEditing)
                        Button {
                            if isEditing {
                                draft = saved
                            }
                            isEditing.toggle()
                        } label: {
                            Label(isEditing ? "편집 취소" : "수정", systemImage: isEditing ? "xmark" : "pencil")
                                .frame(minHeight: MemdoMetrics.touchTarget)
                        }
                        .buttonStyle(.bordered)
                    }

                    if isEditing {
                        ScheduleEditorFields(schedule: $draft)
                    } else {
                        ScheduleMetadataCard(schedule: draft)
                    }
                }
                .padding(20)
            }
            .background(MemdoPageBackground())
            .navigationTitle("일정 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "저장" : "완료") {
                        if isEditing {
                            saved = draft
                            onSave(draft)
                            isEditing = false
                        } else {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ScheduleDetailHeader: View {
    let schedule: ScheduleDetail

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ScheduleSourceIcon(source: schedule.source)
                .scaleEffect(1.15)
            VStack(alignment: .leading, spacing: 5) {
                Text(schedule.source)
                    .font(.caption.bold())
                    .foregroundStyle(MemdoTheme.secondaryInk)
                Text(schedule.title)
                    .font(.title2.bold())
                    .foregroundStyle(MemdoTheme.ink)
                Text("7월 \(schedule.day)일 · \(schedule.time)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MemdoTheme.accent)
            }
        }
    }
}

private struct ScheduleStatusButton: View {
    @Binding var isDone: Bool
    let onChange: () -> Void

    var body: some View {
        Button {
            isDone.toggle()
            onChange()
        } label: {
            Label(isDone ? "완료됨" : "완료로 표시", systemImage: isDone ? "checkmark.circle.fill" : "circle")
                .frame(minHeight: MemdoMetrics.touchTarget)
        }
        .buttonStyle(.bordered)
        .tint(isDone ? MemdoTheme.mine : MemdoTheme.accent)
    }
}

private struct ScheduleMetadataCard: View {
    let schedule: ScheduleDetail

    var body: some View {
        VStack(spacing: 0) {
            MetadataLine(icon: "mappin.and.ellipse", title: "장소", value: schedule.location.nilFallback)
            Divider().padding(.leading, 50)
            MetadataLine(icon: "bell", title: "알림", value: schedule.reminder)
            Divider().padding(.leading, 50)
            MetadataLine(icon: "repeat", title: "반복", value: schedule.repeatRule)
            Divider().padding(.leading, 50)
            MetadataLine(icon: "note.text", title: "메모", value: schedule.memo.nilFallback)
        }
        .memdoCard()
    }
}

private struct MetadataLine: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(MemdoTheme.accent)
                .frame(width: 30)
            Text(title)
                .foregroundStyle(MemdoTheme.secondaryInk)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(MemdoTheme.ink)
        }
        .font(.subheadline)
        .padding(16)
    }
}

struct ScheduleEditorFields: View {
    @Binding var schedule: ScheduleDetail

    var body: some View {
        VStack(spacing: 14) {
            TextField("일정 제목", text: $schedule.title)
                .font(.headline)
                .memdoField()

            HStack {
                Label("날짜", systemImage: "calendar")
                    .foregroundStyle(MemdoTheme.secondaryInk)
                Spacer()
                Picker("날짜", selection: $schedule.day) {
                    ForEach(1...31, id: \.self) { day in
                        Text("7월 \(day)일").tag(day)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .memdoField()

            ScheduleEditorRow(icon: "clock", title: "시간", placeholder: "09:00", text: $schedule.time)
            ScheduleEditorRow(icon: "mappin.and.ellipse", title: "장소", placeholder: "없음", text: $schedule.location)
            ScheduleEditorRow(icon: "bell", title: "알림", placeholder: "없음", text: $schedule.reminder)
            ScheduleEditorRow(icon: "repeat", title: "반복", placeholder: "반복 안 함", text: $schedule.repeatRule)

            VStack(alignment: .leading, spacing: 10) {
                Label("메모", systemImage: "note.text")
                    .foregroundStyle(MemdoTheme.secondaryInk)
                TextField("메모 없음", text: $schedule.memo, axis: .vertical)
                    .lineLimit(3...6)
            }
            .memdoField()
        }
    }
}

private struct ScheduleEditorRow: View {
    let icon: String
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: icon)
                .foregroundStyle(MemdoTheme.secondaryInk)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
        }
        .memdoField()
    }
}

struct AddScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleDetail

    let onSave: (ScheduleDetail) -> Void

    init(day: Int, onSave: @escaping (ScheduleDetail) -> Void) {
        _draft = State(initialValue: .init(day: day, time: "09:00", title: ""))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("7월 \(draft.day)일")
                        .font(.subheadline.bold())
                        .foregroundStyle(MemdoTheme.accent)
                    ScheduleEditorFields(schedule: $draft)
                }
                .padding(20)
            }
            .background(MemdoPageBackground())
            .navigationTitle("새 일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private extension String {
    var nilFallback: String { isEmpty ? "없음" : self }
}

private extension View {
    func memdoField() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
                    .stroke(MemdoTheme.outline)
            }
    }
}
