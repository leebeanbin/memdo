import MapKit
import SwiftUI

struct ScheduleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: ScheduleDetail
    @State private var saved: ScheduleDetail
    @State private var isEditing = false
    @State private var showsDeleteConfirmation = false

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
                            .memdoToggle()
                            if let mins = draft.estimatedMinutes {
                                LabeledContent("소요 시간", value: ScheduleDuration.label(for: mins))
                            }
                        }
                    }

                    Section("일정 정보") {
                        if let url = draft.linkURL {
                            Link(destination: url) {
                                if let provider = MeetingProvider.recognized(url) {
                                    Label("\(provider.label) 참여", systemImage: provider.systemImage)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(MemdoTheme.accent)
                                } else {
                                    Label("링크 열기", systemImage: "link")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(MemdoTheme.accent)
                                }
                            }
                        } else if let meetingURL = draft.meetingURL, let provider = draft.meetingProvider {
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
                        if let mapURL = draft.appleMapsURL {
                            Link(destination: mapURL) {
                                LabeledContent("장소", value: draft.location)
                                    .foregroundStyle(MemdoTheme.accent)
                            }
                        } else {
                            LabeledContent("장소", value: draft.location.isEmpty ? "없음" : draft.location)
                        }
                        if draft.isExternal {
                            LabeledContent("출처", value: draft.calendar.title)
                        } else {
                            LabeledContent("알림", value: draft.reminder)
                            // repeatRule isn't round-tripped from the server (the todo
                            // response only carries scheduleRuleId, not the rule's
                            // frequency) -- reflect presence rather than a value that's
                            // always "반복 안 함" even when the row does repeat.
                            LabeledContent("반복", value: draft.scheduleRuleId != nil ? "반복 중" : "반복 안 함")
                            LabeledContent("메모", value: draft.memo.nilFallback)
                        }
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
            .navigationTitle(isEditing && dynamicTypeSize.isAccessibilitySize ? "수정" : "일정 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditing ? "취소" : "닫기") { cancelOrDismiss() }
                        .foregroundStyle(MemdoTheme.accent)
                }
                if !draft.isExternal {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            Button(isEditing ? "저장" : "수정") { editOrSave() }
                                .fontWeight(.semibold)
                                .disabled(!canSave)
                            if !isEditing {
                                Menu {
                                    Button("삭제", systemImage: "trash", role: .destructive) {
                                        showsDeleteConfirmation = true
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                }
                                .accessibilityLabel("일정 더보기")
                            }
                        }
                    }
                }
            }
        }
        .memdoSheetPresentation([.large])
        .onChange(of: liveVersion) { _, _ in resyncVersionFromStore() }
        .confirmationDialog(
            "일정을 삭제할까요?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(draft.scheduleRuleId == nil ? "삭제" : "이 일정만 삭제", role: .destructive) {
                scheduleStore.delete(id: draft.id)
                dismiss()
            }
            if let ruleId = draft.scheduleRuleId {
                Button("이후 반복 모두 삭제", role: .destructive) {
                    scheduleStore.deleteRecurring(ruleId: ruleId)
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                draft.scheduleRuleId == nil
                    ? "일정이 목록에서 삭제됩니다."
                    : "반복 전체 삭제는 오늘 이후의 반복 일정을 모두 정리하고, 지난 기록은 남겨둡니다."
            )
        }
    }

    private func resyncVersionFromStore() {
        guard let live = scheduleStore.schedules.first(where: { $0.id == draft.id }) else { return }
        saved = live
        if isEditing {
            // Don't clobber an in-progress edit's fields, just keep version and
            // materialization state current -- e.g. a virtual occurrence that
            // got materialized elsewhere while this sheet was open must save via
            // update() (PATCH) next, not create() again (which would 409).
            draft.version = live.version
            draft.isVirtual = live.isVirtual
            draft.scheduleRuleId = live.scheduleRuleId
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
                HStack(spacing: 6) {
                    Text(schedule.source)
                        .font(.caption.bold())
                        .foregroundStyle(MemdoTheme.secondaryInk)
                    if let c = schedule.color {
                        Circle()
                            .fill(c.swiftUIColor)
                            .frame(width: 8, height: 8)
                    }
                }
                HStack(spacing: 4) {
                    if let emoji = schedule.emoji, !emoji.isEmpty {
                        Text(emoji).font(.headline)
                    }
                    Text(schedule.title)
                        .font(.headline)
                        .foregroundStyle(MemdoTheme.ink)
                }
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

                    HStack(spacing: 6) {
                        Button {
                            startBinding.wrappedValue = .now
                        } label: {
                            Label("지금으로", systemImage: "clock.badge.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.mini)
                        .foregroundStyle(MemdoTheme.brand)

                        Spacer(minLength: 0)

                        ForEach([30, 60, 120] as [Int], id: \.self) { mins in
                            Button(ScheduleDuration.label(for: mins)) {
                                endBinding.wrappedValue = (schedule.startAt ?? .now)
                                    .addingTimeInterval(Double(mins * 60))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.mini)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                    }

                    DatePicker(
                        "종료",
                        selection: endBinding,
                        in: startBinding.wrappedValue...,
                        displayedComponents: datePickerComponents
                    )
                    .datePickerStyle(.compact)
                    Toggle("종일", isOn: $schedule.isAllDay)
                        .memdoToggle()

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
                HStack(spacing: 8) {
                    if let url = schedule.linkURL {
                        Image(systemName: MeetingProvider.recognized(url) != nil ? "video.fill" : "link")
                            .foregroundStyle(MemdoTheme.brand)
                            .frame(width: 20)
                    }
                    TextField("링크 (Zoom, Meet, Docs 등)", text: meetingLinkBinding)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.ink)
                    if schedule.meetingURLString != nil {
                        Button {
                            schedule.meetingURLString = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("링크 제거")
                    }
                }
                NavigationLink {
                    LocationPickerView(currentLocation: schedule.locationValue) {
                        schedule.locationValue = $0
                    }
                } label: {
                    LabeledContent("장소", value: schedule.location.nilFallback)
                }
                Picker("미리 알림", selection: $schedule.reminderOffsetMinutes) {
                    ForEach(ScheduleReminderOption.options) { option in
                        Text(option.label).tag(option.offsetMinutes)
                    }
                }
                .pickerStyle(.menu)
                if schedule.kind == .task {
                    Picker("소요 시간", selection: $schedule.estimatedMinutes) {
                        Text("없음").tag(nil as Int?)
                        ForEach(ScheduleDuration.allCases) { d in
                            Text(d.label).tag(d.rawValue as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                }
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

            Section("서식") {
                HStack(spacing: 8) {
                    TextField("이모지", text: emojiBinding)
                        .frame(width: 36)
                        .multilineTextAlignment(.center)
                        .font(.title3)
                    Spacer(minLength: 4)
                    ForEach(ScheduleColor.allCases) { c in
                        let selected = schedule.color == c
                        Circle()
                            .fill(c.swiftUIColor)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().stroke(.primary, lineWidth: selected ? 2 : 0)
                                    .padding(2)
                            )
                            .scaleEffect(selected ? 1.12 : 1, anchor: .center)
                            .animation(.easeInOut(duration: 0.15), value: selected)
                            .onTapGesture { schedule.color = selected ? nil : c }
                            .accessibilityLabel(c.label)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .frame(minHeight: 36)
                .padding(.vertical, 4)
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
                        Button("준비물 제안", systemImage: "list.bullet", action: suggestPreparation)
                    } label: {
                        Label("빠른 서식", systemImage: "text.badge.checkmark")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel("빠른 서식 도구")
                }
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
        let cal = Calendar.current
        guard cal.isDateInToday(schedule.scheduledDate) else {
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: schedule.scheduledDate)
                ?? schedule.scheduledDate
        }
        let now = Date.now
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let nextHour = minute == 0 ? hour : hour + 1
        return cal.date(bySettingHour: min(nextHour, 23), minute: 0, second: 0, of: schedule.scheduledDate)
            ?? schedule.scheduledDate
    }

    private var emojiBinding: Binding<String> {
        Binding(
            get: { schedule.emoji ?? "" },
            set: { new in
                let single = new.unicodeScalars.first { $0.properties.isEmojiPresentation }
                schedule.emoji = single.map(String.init) ?? (new.isEmpty ? nil : schedule.emoji)
            }
        )
    }

    private var meetingLinkBinding: Binding<String> {
        Binding(
            get: { schedule.meetingURLString ?? "" },
            set: { new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                schedule.meetingURLString = trimmed.isEmpty ? nil : trimmed
            }
        )
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
        if let url = event.meetingURL { draft.meetingURLString = url.absoluteString }
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
        let cal = Calendar.current
        let startAt: Date
        if cal.isDateInToday(date) {
            let now = Date.now
            let hour = cal.component(.hour, from: now)
            let minute = cal.component(.minute, from: now)
            let nextHour = minute == 0 ? hour : hour + 1
            startAt = cal.date(bySettingHour: min(nextHour, 23), minute: 0, second: 0, of: date) ?? date
        } else {
            startAt = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
        return ScheduleDetail(
            scheduledDate: date,
            startAt: startAt,
            endAt: cal.date(byAdding: .hour, value: 1, to: startAt) ?? startAt,
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
    @State private var selectedIndex: Int?
    @State private var cameraPosition: MapCameraPosition = .automatic

    let currentLocation: ScheduleLocation?
    let onSelect: (ScheduleLocation?) -> Void

    private var selectedItem: MKMapItem? {
        selectedIndex.flatMap { results.indices.contains($0) ? results[$0] : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                    Marker(item.name ?? "장소", coordinate: item.placemark.coordinate)
                        .tint(index == selectedIndex ? MemdoTheme.brand : MemdoTheme.controlOutline)
                }
            }
            .mapStyle(.standard)
            .frame(height: 220)

            List {
                if let currentLocation {
                    Section("저장된 장소") {
                        Button(currentLocation.displayText) {
                            onSelect(currentLocation)
                            dismiss()
                        }
                        .foregroundStyle(MemdoTheme.ink)
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
                        ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                            Button { select(at: index) } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name ?? "이름 없는 장소")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(MemdoTheme.ink)
                                        if let address = item.placemark.title {
                                            Text(address)
                                                .font(.caption)
                                                .foregroundStyle(MemdoTheme.secondaryInk)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if index == selectedIndex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(MemdoTheme.brand)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
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
        }
        .searchable(text: $query, prompt: "건물, 상호, 주소")
        .onSubmit(of: .search, search)
        .navigationTitle("장소")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let item = selectedItem {
                ToolbarItem(placement: .confirmationAction) {
                    Button("선택") { confirm(item) }
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: selectedIndex) { _, index in
            guard let index, results.indices.contains(index) else { return }
            let coord = results[index].placemark.coordinate
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                ))
            }
        }
        .onChange(of: results) { _, newResults in
            selectedIndex = nil
            guard !newResults.isEmpty else { return }
            if newResults.count == 1 {
                cameraPosition = .region(MKCoordinateRegion(
                    center: newResults[0].placemark.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                ))
            } else {
                cameraPosition = .automatic
            }
        }
    }

    private func select(at index: Int) {
        if selectedIndex == index {
            // double-tap = immediate confirm
            if let item = selectedItem { confirm(item) }
        } else {
            selectedIndex = index
        }
    }

    private func confirm(_ item: MKMapItem) {
        onSelect(ScheduleLocation(
            name: item.name ?? "장소",
            address: item.placemark.title,
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            provider: .appleMaps
        ))
        dismiss()
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
}

private extension ScheduleDetail {
    var appleMapsURL: URL? {
        guard let locationValue else { return nil }
        if let lat = locationValue.latitude, let lng = locationValue.longitude {
            let q = (locationValue.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
            return URL(string: "maps://?ll=\(lat),\(lng)&q=\(q)")
        }
        guard let q = locationValue.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "maps://?q=\(q)")
    }
}

private enum ScheduleDuration: Int, CaseIterable, Identifiable {
    case min15 = 15
    case min30 = 30
    case min45 = 45
    case hour1 = 60
    case hour90 = 90
    case hour2 = 120
    case hour3 = 180
    case hour4 = 240
    case hour6 = 360
    case hour8 = 480

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .min15:  "15분"
        case .min30:  "30분"
        case .min45:  "45분"
        case .hour1:  "1시간"
        case .hour90: "1시간 30분"
        case .hour2:  "2시간"
        case .hour3:  "3시간"
        case .hour4:  "4시간"
        case .hour6:  "6시간"
        case .hour8:  "8시간"
        }
    }

    static func label(for minutes: Int) -> String {
        allCases.first { $0.rawValue == minutes }?.label
            ?? (minutes < 60 ? "\(minutes)분" : "\(minutes / 60)시간 \(minutes % 60 == 0 ? "" : "\(minutes % 60)분")".trimmingCharacters(in: .whitespaces))
    }
}
