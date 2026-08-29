import SwiftUI
import PhotosUI

// MARK: - Compact Row (Today / Calendar)

struct WorkoutLogRow: View {
    let workout: WorkoutLog
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 활동 아이콘
                ZStack {
                    Circle()
                        .fill(activityColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: workout.activityType.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(activityColor)
                }

                // 제목 + 통계
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.activityType.label)
                        .font(MemdoTypography.action)
                        .foregroundStyle(MemdoTheme.ink)
                    HStack(spacing: 6) {
                        Text(workout.durationFormatted)
                        if let d = workout.distanceFormatted {
                            Text("·"); Text(d)
                        }
                        if let cal = workout.calories {
                            Text("·"); Text("\(Int(cal))kcal")
                        }
                    }
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                }

                Spacer()

                // 심박수
                if let hr = workout.avgHeartRate {
                    Label("\(Int(hr))", systemImage: "heart.fill")
                        .font(MemdoTypography.caption2Emphasis)
                        .foregroundStyle(Color.pink)
                }
            }
            .padding(.horizontal, MemdoMetrics.pagePadding)
            .padding(.vertical, 10)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var activityColor: Color { workout.activityType.color }
}

// MARK: - Today Workout Section

struct TodayWorkoutSection: View {
    let workouts: [WorkoutLog]
    let onTap: (WorkoutLog) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 섹션 헤더
            HStack {
                Label("운동", systemImage: "figure.run")
                    .font(MemdoTypography.metric)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                Spacer()
                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("추가")
                    }
                    .font(MemdoTypography.metric)
                    .foregroundStyle(MemdoTheme.brandInk)
                }
            }
            .padding(.horizontal, MemdoMetrics.pagePadding)
            .padding(.bottom, 6)

            if workouts.isEmpty {
                // 빈 상태 — 유저가 선택할 수 있는 두 경로를 암시
                Button(action: onAdd) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(MemdoTheme.brand.opacity(0.1))
                                .frame(width: 36, height: 36)
                            Image(systemName: "figure.run.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(MemdoTheme.brandInk)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("운동 기록 추가")
                                .font(MemdoTypography.action)
                                .foregroundStyle(MemdoTheme.ink)
                            Text("Apple Watch · 운동 앱 · 직접 입력")
                                .font(MemdoTypography.caption)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(MemdoTypography.captionEmphasis)
                            .foregroundStyle(MemdoTheme.secondaryInk.opacity(0.5))
                    }
                    .padding(.horizontal, MemdoMetrics.pagePadding)
                    .padding(.vertical, 10)
                    .background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(workouts) { workout in
                        WorkoutLogRow(workout: workout) { onTap(workout) }
                        if workout.id != workouts.last?.id {
                            Divider().padding(.leading, MemdoMetrics.pagePadding + 48)
                        }
                    }
                }
                .background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
            }
        }
    }
}

// MARK: - Detail Sheet

struct WorkoutDetailSheet: View {
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var showDeleteConfirm = false
    @State private var isTracking = false
    let workout: WorkoutLog

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    imageSection
                    statsGrid

                    if let exercises = workout.exercises, !exercises.isEmpty {
                        exerciseSection(exercises)
                    }

                    if !workout.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("노트", systemImage: "note.text")
                                .font(MemdoTypography.metric)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                            Text(workout.notes)
                                .font(MemdoTypography.subtitle)
                                .foregroundStyle(MemdoTheme.ink)
                        }
                        .padding(MemdoMetrics.pagePadding)
                    }

                    // Live 추적 버튼 — 현재 진행 중인 운동에만 표시
                    if workout.startedAt <= .now && workout.endedAt >= .now {
                        trackingSection
                    }
                }
                .padding(.bottom, 40)
            }
            .background(MemdoPageBackground())
            .navigationTitle(workout.activityType.label)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("편집", systemImage: "pencil") { editing = true }
                        Button("삭제", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $editing) {
                WorkoutLogEditorSheet(workout: workout)
            }
            .confirmationDialog("운동 기록을 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    WorkoutActivityTracker.cancel(workoutID: workout.id)
                    workoutStore.delete(workout)
                    dismiss()
                }
            }
        }
        .onAppear { isTracking = WorkoutActivityTracker.isTracking(workoutID: workout.id) }
    }

    private var trackingSection: some View {
        VStack(spacing: 10) {
            if isTracking {
                Button {
                    WorkoutActivityTracker.complete(workoutID: workout.id)
                    isTracking = false
                } label: {
                    Label("운동 완료", systemImage: "checkmark.circle.fill")
                        .font(MemdoTypography.action)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.green, in: RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, MemdoMetrics.pagePadding)
            } else {
                Button {
                    WorkoutActivityTracker.start(
                        workoutID: workout.id,
                        activityType: workout.activityType.rawValue,
                        startedAt: workout.startedAt
                    )
                    isTracking = true
                } label: {
                    Label("Dynamic Island 추적 시작", systemImage: "liveactivity")
                        .font(MemdoTypography.action)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(MemdoTheme.accent, in: RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous))
                        .foregroundStyle(MemdoTheme.onAccent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, MemdoMetrics.pagePadding)
            }
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        if let urlString = workout.routeImageURL ?? workout.photoURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
                    .overlay(ProgressView())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipped()
        }
    }

    private var statsGrid: some View {
        // 타입 추론 부담 분산: 각 optional을 명시적으로 unwrap
        var stats: [(String, String, String)] = [("시간", workout.durationFormatted, "timer")]
        if let d = workout.distanceFormatted  { stats.append(("거리",      d,                   "arrow.triangle.swap")) }
        if let p = workout.paceFormatted      { stats.append(("페이스",    p,                   "speedometer")) }
        if let c = workout.calories           { stats.append(("칼로리",    "\(Int(c))kcal",     "flame")) }
        if let h = workout.avgHeartRate       { stats.append(("평균 심박수", "\(Int(h))bpm",   "heart")) }
        if let l = workout.locationName       { stats.append(("장소",      l,                   "mappin")) }

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(stats, id: \.0) { stat in
                WorkoutStatCard(title: stat.0, value: stat.1, icon: stat.2)
            }
        }
        .padding(.horizontal, MemdoMetrics.pagePadding)
    }

    private func exerciseSection(_ exercises: [ExerciseSet]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("세트 기록", systemImage: "dumbbell")
                .font(MemdoTypography.metric)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .padding(.horizontal, MemdoMetrics.pagePadding)
            VStack(spacing: 0) {
                ForEach(exercises) { set in
                    HStack {
                        Text(set.name).font(MemdoTypography.action)
                        Spacer()
                        Text(set.summary).font(MemdoTypography.subtitle).foregroundStyle(MemdoTheme.secondaryInk)
                    }
                    .padding(.horizontal, MemdoMetrics.pagePadding)
                    .padding(.vertical, 8)
                    if set.id != exercises.last?.id {
                        Divider().padding(.leading, MemdoMetrics.pagePadding)
                    }
                }
            }
            .background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
            .padding(.horizontal, MemdoMetrics.pagePadding)
        }
    }
}

private struct WorkoutStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.secondaryInk)
            Text(value)
                .font(MemdoTypography.action)
                .foregroundStyle(MemdoTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
    }
}

// MARK: - Editor Sheet (신규 입력 / 편집)

struct WorkoutLogEditorSheet: View {
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var draft: WorkoutLog
    @State private var photoPicker: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isUploading = false
    @State private var isTracking = false

    let isNew: Bool

    init(workout: WorkoutLog? = nil) {
        let now = Date.now
        let base = workout ?? WorkoutLog(
            activityType: .running,
            startedAt: now,
            endedAt: now.addingTimeInterval(1800),
            durationSeconds: 1800
        )
        _draft = State(initialValue: base)
        isNew  = workout == nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── 상단: 활동 종류 선택 (분류) ──────────────────────────
                activityTypePicker
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .systemGroupedBackground))

                // ── 하단: 분류에 맞는 서식 (Form) ────────────────────────
                Form {
                    // 시간 (항상 표시)
                    Section("시간") {
                        DatePicker("시작", selection: $draft.startedAt,
                                   displayedComponents: [.date, .hourAndMinute])
                        DatePicker("종료", selection: $draft.endedAt,
                                   displayedComponents: [.date, .hourAndMinute])
                        LabeledContent("소요 시간") {
                            Text(durationText)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                    }

                    // 거리 — 유산소 운동만 (러닝/사이클/수영/걷기)
                    if draft.activityType.hasDistance {
                        Section("거리") {
                            let isSwim = draft.activityType == .swimming
                            TextField(
                                isSwim ? "거리 (m)" : "거리 (km)",
                                value: Binding(
                                    get: {
                                        guard let m = draft.distanceMeters, m > 0 else { return 0.0 }
                                        return isSwim ? m : m / 1000
                                    },
                                    set: { v in
                                        draft.distanceMeters = v > 0 ? (isSwim ? v : v * 1000) : nil
                                    }
                                ),
                                format: .number
                            )
                            .keyboardType(.decimalPad)

                            if let pace = draft.paceFormatted {
                                LabeledContent("페이스") {
                                    Text(pace + "/km")
                                        .foregroundStyle(MemdoTheme.secondaryInk)
                                }
                            }
                        }
                    }

                    // 근력 운동 — 세트 기록
                    if draft.activityType == .strengthTraining {
                        exerciseSection
                    }

                    // 칼로리 (항상 표시)
                    Section("칼로리") {
                        TextField("소모 칼로리 (kcal)", value: $draft.calories, format: .number)
                            .keyboardType(.decimalPad)
                    }

                    // 장소
                    Section("장소") {
                        TextField("헬스장, 공원, 수영장 등", text: Binding(
                            get: { draft.locationName ?? "" },
                            set: { draft.locationName = $0.isEmpty ? nil : $0 }
                        ))
                    }

                    // 사진 첨부 (Nike RC 캡처 등)
                    Section {
                        let photoLabel = draft.photoURL != nil ? "사진 변경" : "사진 선택"
                        PhotosPicker(selection: $photoPicker, matching: .images) {
                            Label(photoLabel, systemImage: "photo.badge.plus")
                        }
                        .onChange(of: photoPicker) { _, item in
                            Task { photoData = try? await item?.loadTransferable(type: Data.self) }
                        }
                        if let data = photoData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable().scaledToFill()
                                .frame(height: 160).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: MemdoMetrics.iconRadius))
                        }
                    } header: {
                        Text("사진")
                    } footer: {
                        Text("Nike Running Club, Strava 등 앱의 캡처를 첨부할 수 있어요.")
                    }

                    // 노트
                    Section("노트") {
                        TextField("메모", text: $draft.notes, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    // Dynamic Island 추적 — 새 운동만
                    if isNew {
                        Section {
                            Toggle(isOn: $isTracking) {
                                Label("Dynamic Island 추적", systemImage: "liveactivity")
                            }
                            .onChange(of: isTracking) { _, tracking in
                                if tracking {
                                    draft.startedAt = .now
                                    WorkoutActivityTracker.start(
                                        workoutID: draft.id,
                                        activityType: draft.activityType.rawValue,
                                        startedAt: draft.startedAt
                                    )
                                } else {
                                    WorkoutActivityTracker.cancel(workoutID: draft.id)
                                }
                            }
                        } footer: {
                            Text("켜면 Dynamic Island에 경과 시간이 표시돼요. 저장 시 자동 완료.")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "운동 기록 추가" : "운동 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if isTracking { WorkoutActivityTracker.cancel(workoutID: draft.id) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .fontWeight(.semibold)
                        .disabled(isUploading)
                }
            }
            .overlay {
                if isUploading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    // 활동 종류 선택 — 아이콘 + 라벨 타일
    private var activityTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(WorkoutActivityType.allCases) { type in
                    let isSelected = draft.activityType == type
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            draft.activityType = type
                            // 근력 운동으로 바꾸면 거리 초기화
                            if !type.hasDistance { draft.distanceMeters = nil }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: type.systemImage)
                                .font(.system(size: 20, weight: .medium))
                            Text(type.label)
                                .font(MemdoTypography.captionEmphasis)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(isSelected ? MemdoTheme.onAccent : MemdoTheme.ink)
                        .frame(width: 76)
                        .frame(minHeight: 64)
                        .background(
                            isSelected ? MemdoTheme.accent : MemdoTheme.surface,
                            in: RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
                        )
                        .overlay {
                            if !isSelected {
                                RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
                                    .stroke(MemdoTheme.controlOutline, lineWidth: 0.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MemdoMetrics.pagePadding)
        }
    }

    private var durationText: String {
        let sec = max(0, Int(draft.endedAt.timeIntervalSince(draft.startedAt)))
        let h = sec / 3600, m = (sec % 3600) / 60
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }

    private var exercisesBinding: Binding<[ExerciseSet]> {
        Binding(
            get: { draft.exercises ?? [] },
            set: { draft.exercises = $0.isEmpty ? nil : $0 }
        )
    }

    @ViewBuilder
    private var exerciseSection: some View {
        Section {
            ForEach(exercisesBinding) { $set in
                HStack(spacing: 8) {
                    TextField("운동 이름 (예: 벤치프레스)", text: $set.name)
                    Divider()
                    TextField("세트", value: $set.sets, format: .number)
                        .frame(width: 32).multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                    Text("세트").foregroundStyle(MemdoTheme.secondaryInk)
                        .font(MemdoTypography.caption)
                }
            }
            .onDelete { exercisesBinding.wrappedValue.remove(atOffsets: $0) }
            Button {
                var sets = draft.exercises ?? []
                sets.append(ExerciseSet(name: "", sets: 3, reps: 10))
                draft.exercises = sets
            } label: {
                Label("운동 종목 추가", systemImage: "plus")
            }
        } header: {
            Text("세트 기록")
        } footer: {
            Text("종목을 추가하고 세트 수를 기록하세요. 왼쪽으로 쓸어 삭제할 수 있어요.")
        }
    }

    private func save() {
        draft.durationSeconds = max(1, Int(draft.endedAt.timeIntervalSince(draft.startedAt)))
        if isTracking {
            WorkoutActivityTracker.complete(workoutID: draft.id, endedAt: draft.endedAt)
        }
        Task {
            isUploading = true
            defer { isUploading = false }
            if isNew { workoutStore.save(draft) } else { workoutStore.update(draft) }
            dismiss()
        }
    }
}

#Preview("운동 기록 추가") {
    WorkoutLogEditorSheet()
        .environment(WorkoutStore())
}

#Preview("근력 운동 편집") {
    let w = WorkoutLog(
        activityType: .strengthTraining,
        startedAt: .now.addingTimeInterval(-3600),
        endedAt: .now,
        durationSeconds: 3600,
        calories: 350,
        locationName: "강남 헬스장",
        exercises: [
            ExerciseSet(name: "벤치프레스", sets: 4, reps: 10, weightKg: 80),
            ExerciseSet(name: "스쿼트", sets: 3, reps: 12, weightKg: 100)
        ],
        notes: "오늘 컨디션 좋았음"
    )
    return WorkoutLogEditorSheet(workout: w)
        .environment(WorkoutStore())
}

// MARK: - HealthKit Import Sheet

struct HealthKitImportSheet: View {
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var pending: [WorkoutLog] = []
    @State private var selected: Set<UUID> = []
    @State private var phase: ImportPhase = .loading

    enum ImportPhase { case loading, empty, ready, importing, done }

    var body: some View {
        NavigationStack {
            content
                .background(MemdoPageBackground())
                .navigationTitle("HealthKit 가져오기")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { dismiss() }
                            .disabled(phase == .importing)
                    }
                    if case .ready = phase {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("가져오기") { Task { await doImport() } }
                                .disabled(selected.isEmpty)
                                .fontWeight(.semibold)
                        }
                    }
                }
        }
        .task { await loadPending() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading, .importing:
            let label = phase == .loading
                ? "새 운동 기록 확인 중..."
                : "\(selected.count)개 운동 저장 중..."
            VStack(spacing: 14) {
                ProgressView()
                Text(label)
                    .font(MemdoTypography.subtitle)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .done:
            ContentUnavailableView(
                "\(selected.count)개 운동을 저장했어요",
                systemImage: "checkmark.circle.fill",
                description: Text("Memdo 캘린더에서 확인할 수 있어요.")
            )
            .task {
                try? await Task.sleep(for: .milliseconds(900))
                dismiss()
            }

        case .empty:
            ContentUnavailableView(
                "새 운동 기록이 없어요",
                systemImage: "figure.run.circle",
                description: Text("Apple Watch 또는 운동 앱에서 운동을 완료한 후 다시 시도해 보세요.")
            )

        case .ready:
            List {
                Section {
                    ForEach(pending) { workout in
                        Button { toggleSelection(workout.id) } label: {
                            HStack(spacing: 12) {
                                importRow(workout)
                                Spacer()
                                Image(systemName: selected.contains(workout.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(workout.id)
                                                     ? MemdoTheme.brandInk : MemdoTheme.secondaryInk)
                                    .font(MemdoTypography.title3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("가져올 수 있는 운동 \(pending.count)개")
                } footer: {
                    Text("선택한 운동만 Memdo 캘린더에 추가됩니다. HealthKit 원본 데이터는 변경되지 않아요.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(selected.count == pending.count ? "모두 선택 해제" : "모두 선택") {
                        if selected.count == pending.count {
                            selected.removeAll()
                        } else {
                            selected = Set(pending.map(\.id))
                        }
                    }
                    .font(MemdoTypography.footnote)
                }
            }
        }
    }

    private func importRow(_ workout: WorkoutLog) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(workout.activityType.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: workout.activityType.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(workout.activityType.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityType.label)
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.ink)
                HStack(spacing: 6) {
                    Text(workout.startedAt.formatted(.dateTime.month().day().hour().minute()))
                    if let d = workout.distanceFormatted {
                        Text("·"); Text(d)
                    }
                    Text("·"); Text(workout.durationFormatted)
                }
                .font(MemdoTypography.caption)
                .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func loadPending() async {
        let workouts = await workoutStore.fetchPendingFromHealthKit()
        pending = workouts
        selected = Set(workouts.map(\.id))
        phase = workouts.isEmpty ? .empty : .ready
    }

    private func doImport() async {
        phase = .importing
        for workout in pending where selected.contains(workout.id) {
            workoutStore.save(workout)
        }
        withAnimation { phase = .done }
    }
}
