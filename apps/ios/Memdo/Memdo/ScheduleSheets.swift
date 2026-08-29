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
    @State private var editRepeat: ScheduleRepeatRule? = nil

    let onSave: (ScheduleDetail) -> Void

    private var canSave: Bool {
        draft.hasValidTitle && draft.isTimeRangeValid
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
                    if draft.scheduleRuleId != nil {
                        Section {
                            Picker("새 반복 주기", selection: $editRepeat) {
                                Text("변경 안 함").tag(ScheduleRepeatRule?.none)
                                Text("반복 해제").tag(Optional(ScheduleRepeatRule.never))
                                ForEach(ScheduleRepeatRule.allCases.filter { $0 != .never }) { rule in
                                    Text(rule.label).tag(Optional(rule))
                                }
                            }
                        } header: {
                            Text("반복 수정")
                        } footer: {
                            if let rule = editRepeat {
                                Text(rule == .never
                                     ? "이 일정 이후의 반복이 모두 해제됩니다."
                                     : "이 일정부터 '\(rule.label)' 반복이 적용됩니다.")
                            }
                        }
                    }
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
                Task { try? await scheduleStore.delete(id: draft.id) }
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
            editRepeat = nil
            isEditing = false
        } else {
            dismiss()
        }
    }

    private func editOrSave() {
        if isEditing {
            if let ruleId = saved.scheduleRuleId, let newRule = editRepeat {
                if newRule == .never {
                    scheduleStore.deleteRecurring(ruleId: ruleId)
                    draft.scheduleRuleId = nil
                } else {
                    scheduleStore.deleteRecurring(ruleId: ruleId)
                    var recurringDraft = draft
                    recurringDraft.repeatRule = newRule
                    recurringDraft.scheduleRuleId = nil
                    Task { await scheduleStore.createRecurring(recurringDraft) }
                }
                editRepeat = nil
            } else {
                saved = draft
                onSave(draft)
            }
            isEditing = false
        } else {
            editRepeat = nil
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
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                    if let c = schedule.color {
                        Circle()
                            .fill(c.swiftUIColor)
                            .frame(width: 8, height: 8)
                    }
                }
                HStack(spacing: 4) {
                    if let emoji = schedule.emoji, !emoji.isEmpty {
                        Text(emoji).font(MemdoTypography.sectionTitle)
                    }
                    Text(schedule.title)
                        .font(MemdoTypography.sectionTitle)
                        .foregroundStyle(MemdoTheme.ink)
                }
                Text("\(schedule.dateText) · \(schedule.displayTime)")
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.accent)
            }
        }
    }
}

struct ScheduleEditorFields: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Binding var schedule: ScheduleDetail
    var allowsRecurrence = false
    var isEmbedded = false

    var body: some View {
        Group {
            Section("기본 정보") {
                TextField("일정 제목", text: $schedule.title)
                if !isEmbedded {
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
                            ForEach(scheduleStore.calendars) { cal in
                                Button { schedule.calendar = cal } label: {
                                    Label(
                                        cal.title,
                                        systemImage: schedule.calendar == cal ? "checkmark" : cal.provider.systemImage
                                    )
                                }
                            }
                        }
                    } label: {
                        LabeledContent("분류", value: "\(schedule.kind.label) · \(schedule.calendar.title)")
                    }
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
                        .font(MemdoTypography.footnote)
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
                        .font(MemdoTypography.subtitle)
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
                    LabeledContent("반복", value: schedule.scheduleRuleId != nil ? "반복 중 (아래에서 변경)" : "반복 안 함")
                }
            }

            if !isEmbedded { Section("서식") {
                HStack {
                    TextField("이모지", text: emojiBinding)
                        .frame(width: 36, alignment: .center)
                        .multilineTextAlignment(.center)
                        .font(MemdoTypography.title3)
                    Spacer()
                    HStack(spacing: 8) {
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
                }
                .frame(minHeight: 36)
                .padding(.vertical, 4)
            } }  // if !isEmbedded

            Section {
                TextField("메모 없음", text: $schedule.memo, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                HStack {
                    Text("노트")
                    Spacer()
                    Menu {
                        Button("기본 서식 삽입", systemImage: "text.alignleft", action: tidyNote)
                        Button("할 일 목록 삽입", systemImage: "checklist", action: splitNote)
                        Button("준비 항목 삽입", systemImage: "list.bullet", action: suggestPreparation)
                    } label: {
                        Label("빠른 서식", systemImage: "text.badge.checkmark")
                            .font(MemdoTypography.captionEmphasis)
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

// MARK: - Category type for new-entry picker

private enum AddCategory: Equatable {
    case task, event, workout
    case custom(ScheduleUserCategory)

    var label: String {
        switch self {
        case .task:          "할 일"
        case .event:         "시간 일정"
        case .workout:       "운동"
        case .custom(let c): c.name
        }
    }
    var emoji: String {
        switch self {
        case .task:          "✅"
        case .event:         "📅"
        case .workout:       "🏃"
        case .custom(let c): c.emoji
        }
    }
    var accentColor: Color {
        switch self {
        case .task:          MemdoTheme.accent
        case .event:         .blue
        case .workout:       .orange
        case .custom(let c): c.color.swiftUIColor
        }
    }
    var scheduleKind: ScheduleKind {
        switch self {
        case .task, .workout: .task
        case .event:          .event
        case .custom(let c):  c.isTaskKind ? .task : .event
        }
    }
    var scheduleColor: ScheduleColor? {
        switch self {
        case .task:          nil
        case .event:         .sky
        case .workout:       .coral
        case .custom(let c): c.color
        }
    }
    var systemImage: String {
        switch self {
        case .task:          "checkmark.square.fill"
        case .event:         "calendar"
        case .workout:       "figure.run"
        case .custom:        "tag.fill"
        }
    }
    var isWorkout: Bool { self == .workout }
}

// MARK: - AddScheduleSheet

struct AddScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(WorkoutStore.self) private var workoutStore

    @State private var selectedCategory: AddCategory = .task
    @State private var draft: ScheduleDetail
    @State private var showCapture = false
    @State private var userCategories: [ScheduleUserCategory] = []
    @State private var showAddCategory = false

    // Workout-specific state
    @State private var workoutActivityType: WorkoutActivityType = .running
    @State private var workoutStartAt: Date
    @State private var workoutEndAt: Date
    @State private var workoutDistanceText = ""
    @State private var workoutCaloriesText = ""
    @State private var workoutLocation = ""
    @State private var workoutNotes = ""

    let onSave: (ScheduleDetail) -> Void

    private var canSave: Bool {
        if selectedCategory.isWorkout {
            return workoutStartAt < workoutEndAt
        }
        return draft.hasValidTitle
            && UUID(uuidString: draft.calendar.id) != nil
            && draft.isTimeRangeValid
    }

    init(date: Date, defaultKind: ScheduleKind? = nil, onSave: @escaping (ScheduleDetail) -> Void) {
        let d = Self.makeDraft(for: date)
        _draft = State(initialValue: d)
        _workoutStartAt = State(initialValue: d.startAt ?? date)
        _workoutEndAt   = State(initialValue: d.endAt   ?? date.addingTimeInterval(3_600))
        _selectedCategory = State(initialValue: defaultKind == .event ? .event : .task)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── 분류 (색상 아이콘 포함, 캘린더 통합) ─────
                Section {
                    Menu {
                        Section("유형") {
                            nativeCategoryButton(.task)
                            nativeCategoryButton(.event)
                            nativeCategoryButton(.workout)
                        }
                        if !userCategories.isEmpty {
                            Section("내 카테고리") {
                                ForEach(userCategories) { cat in
                                    nativeCategoryButton(.custom(cat))
                                }
                            }
                        }
                        if !selectedCategory.isWorkout && !scheduleStore.calendars.isEmpty {
                            Divider()
                            Section("캘린더") {
                                ForEach(scheduleStore.calendars) { cal in
                                    Button { draft.calendar = cal } label: {
                                        Label(
                                            cal.title,
                                            systemImage: draft.calendar == cal ? "checkmark" : cal.provider.systemImage
                                        )
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("카테고리 추가", systemImage: "plus") { showAddCategory = true }
                    } label: {
                        HStack {
                            Text("분류")
                                .foregroundStyle(MemdoTheme.ink)
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: selectedCategory.systemImage)
                                    .foregroundStyle(selectedCategory.accentColor)
                                    .imageScale(.small)
                                let calSuffix = selectedCategory.isWorkout ? "" : " · \(draft.calendar.title)"
                                Text(selectedCategory.label + calSuffix)
                                    .foregroundStyle(MemdoTheme.secondaryInk)
                            }
                        }
                    }

                    if !selectedCategory.isWorkout {
                        HStack(spacing: 10) {
                            Text("색상")
                                .foregroundStyle(MemdoTheme.ink)
                            Spacer()
                            ForEach(ScheduleColor.allCases) { c in
                                let isSelected = draft.color == c
                                ZStack {
                                    Circle().fill(c.swiftUIColor)
                                    Circle().fill(MemdoTheme.background).padding(isSelected ? 3 : 26)
                                    Circle().fill(c.swiftUIColor).padding(isSelected ? 6 : 0)
                                }
                                .frame(width: 26, height: 26)
                                .clipShape(Circle())
                                .animation(.easeInOut(duration: 0.15), value: isSelected)
                                .onTapGesture { draft.color = isSelected ? nil : c }
                                .accessibilityLabel(c.label)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if selectedCategory.isWorkout {
                    workoutForm
                } else {
                    Section {
                        Button { showCapture = true } label: {
                            Label("붙여넣기로 채우기", systemImage: "wand.and.stars")
                                .foregroundStyle(MemdoTheme.accent)
                        }
                    }
                    ScheduleEditorFields(schedule: $draft, allowsRecurrence: true, isEmbedded: true)
                }
            }
            .memdoSystemList()
            .navigationTitle("새 일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }.foregroundStyle(MemdoTheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("추가") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showCapture) {
                EventCaptureSheet { applyCapture($0) }
            }
            .sheet(isPresented: $showAddCategory) {
                AddCategorySheet { newCat in
                    userCategories.append(newCat)
                    scheduleStore.replaceUserCategories(userCategories)
                }
            }
        }
        .memdoSheetPresentation([.large])
        .onAppear { userCategories = ScheduleUserCategory.load() }
    }

    @ViewBuilder
    private func nativeCategoryButton(_ category: AddCategory) -> some View {
        Button { selectCategory(category) } label: {
            if selectedCategory == category {
                Label(category.label, systemImage: "checkmark")
            } else {
                Text(category.label)
            }
        }
    }

    @ViewBuilder
    private var workoutForm: some View {
        Section {
            Picker("활동 종류", selection: $workoutActivityType) {
                ForEach(WorkoutActivityType.allCases) { type in
                    Label(type.label, systemImage: type.systemImage).tag(type)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: workoutActivityType) { _, type in
                if !type.hasDistance { workoutDistanceText = "" }
            }
        }

        Section("시간") {
            DatePicker("시작", selection: $workoutStartAt, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
            DatePicker("종료", selection: $workoutEndAt, in: workoutStartAt..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
            let secs = max(Int(workoutEndAt.timeIntervalSince(workoutStartAt)), 0)
            LabeledContent("소요 시간", value: secs > 0 ? formatDuration(secs) : "--")
        }

        if workoutActivityType.hasDistance {
            Section("거리") {
                HStack {
                    TextField("0.0", text: $workoutDistanceText)
                        .keyboardType(.decimalPad)
                    Text(workoutActivityType == .swimming ? "m" : "km")
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }
        }

        Section("칼로리 (kcal)") {
            TextField("0", text: $workoutCaloriesText)
                .keyboardType(.numberPad)
        }

        Section("장소") {
            TextField("장소 (선택)", text: $workoutLocation)
        }

        Section("노트") {
            TextField("메모", text: $workoutNotes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }

    private func selectCategory(_ category: AddCategory) {
        selectedCategory = category
        draft.kind = category.scheduleKind
        draft.color = category.scheduleColor
        if case .custom(let c) = category { draft.emoji = c.emoji }
        else { draft.emoji = nil }
        if category == .event && !draft.hasScheduledTime { addScheduledTime() }
    }

    private func addScheduledTime() {
        draft.startAt = workoutStartAt
        draft.endAt   = workoutEndAt
        draft.timeBucket = .inferred(from: workoutStartAt)
    }

    private func save() {
        if selectedCategory.isWorkout {
            let duration = max(Int(workoutEndAt.timeIntervalSince(workoutStartAt)), 0)
            var distanceMeters: Double? = nil
            if workoutActivityType.hasDistance, let d = Double(workoutDistanceText), d > 0 {
                distanceMeters = workoutActivityType == .swimming ? d : d * 1_000
            }
            let workout = WorkoutLog(
                activityType: workoutActivityType,
                startedAt: workoutStartAt,
                endedAt: workoutEndAt,
                durationSeconds: duration,
                distanceMeters: distanceMeters,
                calories: Double(workoutCaloriesText),
                locationName: workoutLocation.isEmpty ? nil : workoutLocation,
                notes: workoutNotes
            )
            workoutStore.save(workout)
        } else {
            if draft.repeatRule != .never {
                let recurring = draft
                Task { await scheduleStore.createRecurring(recurring) }
            } else {
                onSave(draft)
            }
        }
        dismiss()
    }

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

// MARK: - Add custom category sheet

private struct AddCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "⭐"
    @State private var color: ScheduleColor = .amber
    @State private var isTaskKind = true

    let onAdd: (ScheduleUserCategory) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("카테고리") {
                    HStack(spacing: 12) {
                        TextField("🏷", text: $emoji)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                            .font(MemdoTypography.title2)
                        TextField("이름 (예: 독서, 공부)", text: $name)
                    }
                }
                Section("색상") {
                    HStack(spacing: 12) {
                        ForEach(ScheduleColor.allCases) { c in
                            let isSelected = color == c
                            ZStack {
                                Circle().fill(c.swiftUIColor)
                                Circle().fill(MemdoTheme.background).padding(isSelected ? 3 : 30)
                                Circle().fill(c.swiftUIColor).padding(isSelected ? 6 : 0)
                            }
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                            .animation(.easeInOut(duration: 0.15), value: isSelected)
                            .onTapGesture { color = c }
                            .accessibilityLabel(c.label)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Picker("기본 형식", selection: $isTaskKind) {
                        Text("할 일").tag(true)
                        Text("시간 일정").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .memdoSystemList()
            .navigationTitle("카테고리 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }.foregroundStyle(MemdoTheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("추가") {
                        onAdd(ScheduleUserCategory(id: UUID(), name: name, emoji: emoji, color: color, isTaskKind: isTaskKind))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(MemdoTheme.accent)
                }
            }
        }
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
                        .tint(index == selectedIndex ? MemdoTheme.brand : .gray)
                }
            }
            .mapStyle(.standard)
            .frame(height: 220)

            Divider()

            List {
                // 저장된 장소 — 검색 전에만 표시
                if let currentLocation, query.isEmpty {
                    locationRow(
                        name: currentLocation.displayText,
                        address: nil,
                        icon: "mappin.circle.fill",
                        tint: MemdoTheme.brand,
                        isSelected: false
                    ) {
                        onSelect(currentLocation)
                        dismiss()
                    }
                    .listRowSeparator(.hidden)
                }

                // 검색 결과 / 안내
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView().tint(MemdoTheme.secondaryInk)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if results.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: query.isEmpty ? "magnifyingglass" : "mappin.slash")
                            .foregroundStyle(MemdoTheme.secondaryInk)
                        Text(query.isEmpty ? "건물명, 상호 또는 주소로 검색하세요" : "결과를 찾지 못했어요")
                            .font(MemdoTypography.subtitle)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                        locationRow(
                            name: item.name ?? "이름 없는 장소",
                            address: item.placemark.title,
                            icon: "mappin.circle.fill",
                            tint: index == selectedIndex ? MemdoTheme.brand : Color.secondary,
                            isSelected: index == selectedIndex
                        ) {
                            select(at: index)
                        }
                        .listRowBackground(
                            index == selectedIndex
                                ? MemdoTheme.brand.opacity(0.07)
                                : Color.clear
                        )
                        .listRowSeparator(index < results.count - 1 ? .visible : .hidden, edges: .bottom)
                    }
                }

                // 장소 지우기
                if currentLocation != nil {
                    Button(role: .destructive) {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label("장소 지우기", systemImage: "trash")
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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

    @ViewBuilder
    private func locationRow(
        name: String,
        address: String?,
        icon: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(MemdoTypography.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(MemdoTypography.action)
                        .foregroundStyle(MemdoTheme.ink)
                    if let address {
                        Text(address)
                            .font(MemdoTypography.caption)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

#if DEBUG
#Preview("새 일정 — 라이트") {
    AddScheduleSheet(date: .now, onSave: { _ in })
        .environment(ScheduleStore.preview())
        .environment(WorkoutStore())
}

#Preview("새 일정 — 다크") {
    AddScheduleSheet(date: .now, onSave: { _ in })
        .environment(ScheduleStore.preview())
        .environment(WorkoutStore())
        .preferredColorScheme(.dark)
}
#endif
