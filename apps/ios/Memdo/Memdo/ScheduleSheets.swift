import MapKit
import SwiftUI

struct ScheduleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var draft: ScheduleDetail
    @State private var saved: ScheduleDetail
    @State private var isEditing = false

    let onSave: (ScheduleDetail) -> Void

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.isTimeRangeValid
    }

    // The store's version for this item, once it's been written back by a prior
    // save in this same sheet session. Watched so a second save doesn't reuse a
    // now-stale version and lose the optimistic-lock check on the server.
    private var liveVersion: Int? {
        scheduleStore.schedules.first { $0.id == draft.id }?.version
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
                        if let meetingURL = draft.meetingURL, let provider = draft.meetingProvider {
                            Link(destination: meetingURL) {
                                Label("\(provider.label) 참여", systemImage: provider.systemImage)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(MemdoTheme.accent)
                            }
                        }
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
                        LabeledContent("반복", value: draft.repeatRule.label)
                        LabeledContent("메모", value: draft.memo.nilFallback)
                    }
                    if !draft.attachedLinks.isEmpty {
                        Section("관련 링크") {
                            ForEach(draft.attachedLinks, id: \.self) { url in
                                Link(destination: url) {
                                    Label(url.host ?? url.absoluteString, systemImage: "link")
                                        .foregroundStyle(MemdoTheme.accent)
                                }
                            }
                        }
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
        .onChange(of: liveVersion) { _, _ in resyncVersionFromStore() }
    }

    private func resyncVersionFromStore() {
        guard let live = scheduleStore.schedules.first(where: { $0.id == draft.id }) else { return }
        saved = live
        if isEditing {
            // Don't clobber an in-progress edit's fields, just keep the version
            // current so the eventual save doesn't lose the optimistic-lock check.
            draft.version = live.version
        } else {
            draft = live
        }
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
    var allowsRecurrence = false

    var body: some View {
        Group {
            Section("기본 정보") {
                TextField("일정 제목", text: $schedule.title)
                Menu {
                    Section("유형") {
                        ForEach(ScheduleKind.allCases) { kind in
                            Button { select(kind) } label: {
                                if schedule.kind == kind {
                                    Label(kind.label, systemImage: "checkmark")
                                } else {
                                    Text(kind.label)
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
                } label: {
                    LabeledContent("분류", value: "\(schedule.kind.label) · \(schedule.calendar.title)")
                }
            }

            Section("언제") {
                if schedule.hasScheduledTime {
                    DatePicker("시작", selection: startBinding, displayedComponents: datePickerComponents)
                        .datePickerStyle(.compact)
                    DatePicker(
                        "종료",
                        selection: endBinding,
                        in: startBinding.wrappedValue...,
                        displayedComponents: datePickerComponents
                    )
                    .datePickerStyle(.compact)
                    Toggle("종일", isOn: $schedule.isAllDay)

                    if schedule.kind == .task {
                        Button("시간 제거", systemImage: "clock.badge.xmark", action: removeScheduledTime)
                    }
                } else {
                    DatePicker("날짜", selection: scheduledDateBinding, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    Button("시간 추가", systemImage: "clock", action: addScheduledTime)
                }

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
                    LocationPickerView(currentLocation: schedule.locationValue) {
                        schedule.locationValue = $0
                    }
                } label: {
                    LabeledContent("장소", value: schedule.location.nilFallback)
                }
                Picker("알림", selection: $schedule.reminderOffsetMinutes) {
                    ForEach(ScheduleReminderOption.options) { option in
                        Text(option.label).tag(option.offsetMinutes)
                    }
                }
                .pickerStyle(.menu)
                // 반복은 생성 시에만 규칙(schedule_rules)으로 만든다. 기존 일정의
                // 반복 편집은 아직 미지원이라 값만 표시한다.
                if allowsRecurrence {
                    Picker("반복", selection: $schedule.repeatRule) {
                        ForEach(ScheduleRepeatRule.allCases) { rule in
                            Text(rule.label).tag(rule)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    LabeledContent("반복", value: schedule.repeatRule.label)
                }
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
        .onAppear {
            if schedule.calendar.id.isEmpty, let calendar = scheduleStore.calendars.first {
                schedule.calendar = calendar
            }
        }
    }

    private var datePickerComponents: DatePicker.Components {
        schedule.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { schedule.startAt ?? defaultStart },
            set: { newStart in
                let duration = max(
                    schedule.endAt?.timeIntervalSince(schedule.startAt ?? newStart) ?? 3_600,
                    60
                )
                schedule.startAt = newStart
                schedule.endAt = newStart.addingTimeInterval(duration)
                schedule.scheduledDate = Calendar.current.startOfDay(for: newStart)
                schedule.timeBucket = .inferred(from: newStart)
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { schedule.endAt ?? defaultStart.addingTimeInterval(3_600) },
            set: { schedule.endAt = $0 }
        )
    }

    private var scheduledDateBinding: Binding<Date> {
        Binding(
            get: { schedule.scheduledDate },
            set: { schedule.scheduledDate = Calendar.current.startOfDay(for: $0) }
        )
    }

    private var defaultStart: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: schedule.scheduledDate)
            ?? schedule.scheduledDate
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { schedule.dueAt ?? schedule.endAt ?? defaultStart }, set: { schedule.dueAt = $0 })
    }

    private func addDueDate() {
        schedule.dueAt = schedule.endAt ?? defaultStart
    }

    private func removeDueDate() {
        schedule.dueAt = nil
    }

    private func select(_ kind: ScheduleKind) {
        schedule.kind = kind
        if kind == .event {
            if !schedule.hasScheduledTime { addScheduledTime() }
            schedule.dueAt = nil
            schedule.isDone = false
        }
    }

    private func addScheduledTime() {
        schedule.startAt = defaultStart
        schedule.endAt = defaultStart.addingTimeInterval(3_600)
        schedule.timeBucket = .inferred(from: defaultStart)
    }

    private func removeScheduledTime() {
        schedule.startAt = nil
        schedule.endAt = nil
        schedule.isAllDay = false
        schedule.timeBucket = .anytime
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
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var draft: ScheduleDetail
    @State private var showCapture = false

    let onSave: (ScheduleDetail) -> Void

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UUID(uuidString: draft.calendar.id) != nil
            && draft.isTimeRangeValid
    }

    init(date: Date, onSave: @escaping (ScheduleDetail) -> Void) {
        _draft = State(initialValue: Self.makeDraft(for: date))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Button {
                    showCapture = true
                } label: {
                    Label("붙여넣기로 채우기", systemImage: "wand.and.stars")
                        .foregroundStyle(MemdoTheme.accent)
                }
                ScheduleEditorFields(schedule: $draft, allowsRecurrence: true)
            }
            .memdoSystemList()
            .sheet(isPresented: $showCapture) {
                EventCaptureSheet { event in applyCapture(event) }
            }
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

    // Fills the draft from an extracted proposal. The editor itself is the
    // approval gate — nothing is created until the user taps 추가.
    private func applyCapture(_ event: EventDraft) {
        if !event.title.isEmpty { draft.title = event.title }
        if let start = event.startAt {
            draft.startAt = start
            draft.endAt = event.endAt ?? start.addingTimeInterval(3_600)
            draft.scheduledDate = Calendar.current.startOfDay(for: start)
            draft.timeBucket = .inferred(from: start)
        }
        if !event.notes.isEmpty { draft.memo = event.notes }
    }

    private func save() {
        if draft.repeatRule != .never {
            let recurring = draft
            Task { await scheduleStore.createRecurring(recurring) }
        } else {
            onSave(draft)
        }
        dismiss()
    }

    private static func makeDraft(for date: Date) -> ScheduleDetail {
        let calendar = Calendar.current
        let startAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        return ScheduleDetail(
            scheduledDate: date,
            startAt: startAt,
            endAt: calendar.date(byAdding: .hour, value: 1, to: startAt) ?? startAt,
            title: "",
            calendar: .unassigned,
            timeBucket: .inferred(from: startAt)
        )
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

    let currentLocation: ScheduleLocation?
    let onSelect: (ScheduleLocation?) -> Void

    var body: some View {
        List {
            if let currentLocation {
                Section("현재 장소") {
                    Button(currentLocation.displayText) {
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

            if currentLocation != nil {
                Section {
                    Button("장소 지우기", role: .destructive) {
                        onSelect(nil)
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
        onSelect(ScheduleLocation(
            name: item.name ?? "장소",
            address: item.placemark.title,
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            provider: .appleMaps
        ))
        dismiss()
    }
}

private extension ScheduleDetail {
    var googleMapsURL: URL? {
        guard let locationValue else { return nil }
        if let latitude = locationValue.latitude, let longitude = locationValue.longitude {
            return URL(string: "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)")
        }
        guard let query = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(query)")
    }
}
