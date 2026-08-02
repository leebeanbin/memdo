import MapKit
import SwiftUI

struct ScheduleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleDetail
    @State private var saved: ScheduleDetail
    @State private var isEditing = false

    let onSave: (ScheduleDetail) -> Void

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.isTimeRangeValid
    }

    init(schedule: ScheduleDetail, onSave: @escaping (ScheduleDetail) -> Void) {
        _draft = State(initialValue: schedule)
        _saved = State(initialValue: schedule)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if isEditing {
                    ScheduleEditorFields(schedule: $draft)
                } else {
                    Section {
                        ScheduleDetailHeader(schedule: draft)
                    }

                    if draft.kind == .task {
                        Section("상태") {
                            Toggle("완료", isOn: Binding(
                                get: { draft.isDone },
                                set: { isDone in updateCompletion(isDone) }
                            ))
                        }
                    }

                    Section("일정 정보") {
                        LabeledContent("형식", value: draft.kindLabel)
                        LabeledContent("기간", value: draft.displayTime)
                        if let dueAt = draft.dueAt {
                            LabeledContent("마감", value: dueAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let mapURL = draft.googleMapsURL {
                            Link(destination: mapURL) {
                                LabeledContent("장소", value: draft.location)
                            }
                        } else {
                            LabeledContent("장소", value: "없음")
                        }
                        LabeledContent("알림", value: draft.reminder)
                        LabeledContent("반복", value: draft.repeatRule.rawValue)
                        LabeledContent("메모", value: draft.memo.nilFallback)
                    }
                }
            }
            .memdoSystemList()
            .navigationTitle("일정 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditing ? "취소" : "닫기") { cancelOrDismiss() }
                        .foregroundStyle(MemdoTheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "저장" : "수정") { editOrSave() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .memdoSheetPresentation([.large])
    }

    private func updateCompletion(_ isDone: Bool) {
        draft.isDone = isDone
        saved = draft
        onSave(draft)
    }

    private func cancelOrDismiss() {
        if isEditing {
            draft = saved
            isEditing = false
        } else {
            dismiss()
        }
    }

    private func editOrSave() {
        if isEditing {
            saved = draft
            onSave(draft)
            isEditing = false
        } else {
            isEditing = true
        }
    }

}

private struct ScheduleDetailHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let schedule: ScheduleDetail

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                ScheduleSourceIcon(schedule: schedule)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.source)
                    .font(.caption.bold())
                    .foregroundStyle(MemdoTheme.secondaryInk)
                Text(schedule.title)
                    .font(.headline)
                    .foregroundStyle(MemdoTheme.ink)
                Text("\(schedule.dateText) · \(schedule.displayTime)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MemdoTheme.accent)
            }
        }
    }
}

struct ScheduleEditorFields: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Binding var schedule: ScheduleDetail
    @State private var isAddingCalendar = false
    @State private var newCalendarName = ""

    var body: some View {
        Group {
            Section("기본 정보") {
                TextField("일정 제목", text: $schedule.title)
                Menu {
                    Section("유형") {
                        ForEach(ScheduleKind.allCases) { kind in
                            Button { select(kind) } label: {
                                if schedule.kind == kind {
                                    Label(kind.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(kind.rawValue)
                                }
                            }
                        }
                    }
                    Section("캘린더") {
                        ForEach(scheduleStore.calendars) { calendar in
                            Button { schedule.calendar = calendar } label: {
                                Label(
                                    calendar.title,
                                    systemImage: schedule.calendar == calendar ? "checkmark" : calendar.provider.systemImage
                                )
                            }
                        }
                    }
                    Divider()
                    Button("새 캘린더 추가", systemImage: "plus") {
                        isAddingCalendar = true
                    }
                } label: {
                    LabeledContent("분류", value: "\(schedule.kind.rawValue) · \(schedule.calendar.title)")
                }
            }

            Section("언제") {
                DatePicker("시작", selection: startBinding, displayedComponents: datePickerComponents)
                    .datePickerStyle(.compact)
                DatePicker(
                    "종료",
                    selection: $schedule.endAt,
                    in: schedule.startAt...,
                    displayedComponents: datePickerComponents
                )
                .datePickerStyle(.compact)
                Toggle("종일", isOn: $schedule.isAllDay)

                if !schedule.isTimeRangeValid {
                    Label("종료는 시작보다 뒤여야 해요", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if schedule.kind == .task {
                Section("마감") {
                    if schedule.dueAt != nil {
                        DatePicker("마감", selection: dueBinding, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                        Button("마감일 제거", role: .destructive, action: removeDueDate)
                    } else {
                        Button("마감일 추가", systemImage: "flag", action: addDueDate)
                    }
                }
            }

            Section("선택 정보") {
                NavigationLink {
                    LocationPickerView(currentLocation: schedule.location) {
                        schedule.location = $0
                    }
                } label: {
                    LabeledContent("장소", value: schedule.location.nilFallback)
                }
                LabeledContent("알림") {
                    TextField("예: 30분 전", text: $schedule.reminder)
                        .multilineTextAlignment(.trailing)
                }
                Picker("반복", selection: $schedule.repeatRule) {
                    ForEach(ScheduleRepeatRule.allCases) { rule in
                        Text(rule.rawValue).tag(rule)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                TextField("메모 없음", text: $schedule.memo, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                HStack {
                    Text("노트")
                    Spacer()
                    Menu {
                        Button("문장 정리", systemImage: "text.alignleft", action: tidyNote)
                        Button("할 일로 나누기", systemImage: "checklist", action: splitNote)
                        Button("준비물 제안", systemImage: "sparkles", action: suggestPreparation)
                    } label: {
                        Label("Agent", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel("Agent 노트 도구")
                }
            } footer: {
                Text("Agent는 저장 전에 변경 내용을 항상 보여줘요.")
            }
        }
        .alert("새 캘린더", isPresented: $isAddingCalendar) {
            TextField("예: 사이드 프로젝트", text: $newCalendarName)
            Button("취소", role: .cancel) { newCalendarName = "" }
            Button("추가", action: addCalendar)
                .disabled(newCalendarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("일정을 묶어 볼 이름을 입력하세요.")
        }
    }

    private var datePickerComponents: DatePicker.Components {
        schedule.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { schedule.startAt },
            set: { newStart in
                let duration = max(schedule.endAt.timeIntervalSince(schedule.startAt), 60)
                schedule.startAt = newStart
                schedule.endAt = newStart.addingTimeInterval(duration)
            }
        )
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { schedule.dueAt ?? schedule.endAt }, set: { schedule.dueAt = $0 })
    }

    private func addDueDate() {
        schedule.dueAt = schedule.endAt
    }

    private func removeDueDate() {
        schedule.dueAt = nil
    }

    private func select(_ kind: ScheduleKind) {
        schedule.kind = kind
        if kind == .event {
            schedule.dueAt = nil
            schedule.isDone = false
        }
    }

    private func addCalendar() {
        if let calendar = scheduleStore.addCalendar(named: newCalendarName) {
            schedule.calendar = calendar
        }
        newCalendarName = ""
    }

    private func tidyNote() {
        let note = schedule.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.memo = note.isEmpty ? "목표와 결과를 한 문장으로 정리해 보세요." : note
    }

    private func splitNote() {
        let note = schedule.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.memo = note.isEmpty ? "• 준비하기\n• 실행하기\n• 결과 확인하기" : "• \(note)\n• 결과 확인하기"
    }

    private func suggestPreparation() {
        let prefix = schedule.memo.isEmpty ? "" : "\(schedule.memo)\n"
        schedule.memo = "\(prefix)준비: 관련 자료, 예상 소요 시간, 완료 기준"
    }
}

struct AddScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleDetail

    let onSave: (ScheduleDetail) -> Void

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.isTimeRangeValid
    }

    init(day: Int, onSave: @escaping (ScheduleDetail) -> Void) {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: day)) ?? .now
        _draft = State(initialValue: Self.makeDraft(for: date))
        self.onSave = onSave
    }

    init(date: Date, onSave: @escaping (ScheduleDetail) -> Void) {
        _draft = State(initialValue: Self.makeDraft(for: date))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                ScheduleEditorFields(schedule: $draft)
            }
            .memdoSystemList()
            .navigationTitle("새 일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(MemdoTheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("추가") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .memdoSheetPresentation([.large])
    }

    private func save() {
        onSave(draft)
        dismiss()
    }

    private static func makeDraft(for date: Date) -> ScheduleDetail {
        let calendar = Calendar.current
        let startAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        var draft = ScheduleDetail(day: calendar.component(.day, from: date), time: "09:00", title: "")
        draft.startAt = startAt
        draft.endAt = calendar.date(byAdding: .hour, value: 1, to: startAt) ?? startAt
        return draft
    }
}

private extension String {
    var nilFallback: String { isEmpty ? "없음" : self }
}

private struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false

    let currentLocation: String
    let onSelect: (String) -> Void

    var body: some View {
        List {
            if !currentLocation.isEmpty {
                Section("현재 장소") {
                    Button(currentLocation) {
                        onSelect(currentLocation)
                        dismiss()
                    }
                }
            }

            Section("검색 결과") {
                if isSearching {
                    ProgressView("장소를 찾는 중")
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "장소를 검색해 보세요",
                        systemImage: "map",
                        description: Text("건물명, 상호 또는 주소를 입력하세요.")
                    )
                } else {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                        Button { select(item) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? "이름 없는 장소")
                                    .foregroundStyle(MemdoTheme.ink)
                                if let address = item.placemark.title {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(MemdoTheme.secondaryInk)
                                }
                            }
                        }
                    }
                }
            }

            if !currentLocation.isEmpty {
                Section {
                    Button("장소 지우기", role: .destructive) {
                        onSelect("")
                        dismiss()
                    }
                }
            }
        }
        .memdoSystemList()
        .searchable(text: $query, prompt: "건물, 상호, 주소")
        .onSubmit(of: .search, search)
        .navigationTitle("장소")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            let response = try? await MKLocalSearch(request: request).start()
            results = response?.mapItems ?? []
            isSearching = false
        }
    }

    private func select(_ item: MKMapItem) {
        let name = item.name ?? "장소"
        let address = item.placemark.title ?? ""
        onSelect(address.isEmpty || address == name ? name : "\(name) · \(address)")
        dismiss()
    }
}

private extension ScheduleDetail {
    var googleMapsURL: URL? {
        guard !location.isEmpty,
              let query = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(query)")
    }
}
