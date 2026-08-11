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
                        .font(.subheadline.weight(.semibold))
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
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                }

                Spacer()

                // 심박수
                if let hr = workout.avgHeartRate {
                    Label("\(Int(hr))", systemImage: "heart.fill")
                        .font(.caption2.weight(.medium))
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

    private var activityColor: Color {
        switch workout.activityType {
        case .running:          .orange
        case .cycling:          .green
        case .swimming:         .blue
        case .strengthTraining: .purple
        case .yoga:             .teal
        case .hiit:             .red
        case .walking:          .mint
        case .other:            MemdoTheme.brand
        }
    }
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MemdoTheme.secondaryInk)
                Spacer()
                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("추가")
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MemdoTheme.brand)
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
                                .foregroundStyle(MemdoTheme.brand)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("운동 기록 추가")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(MemdoTheme.ink)
                            Text("Apple Watch · 운동 앱 · 직접 입력")
                                .font(.caption)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
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
    @State private var editing = false
    let workout: WorkoutLog

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 경로 이미지 또는 첨부 사진
                    imageSection

                    // 핵심 수치
                    statsGrid

                    // 세트 기록 (근력 운동)
                    if let exercises = workout.exercises, !exercises.isEmpty {
                        exerciseSection(exercises)
                    }

                    // 노트
                    if !workout.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("노트", systemImage: "note.text")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(MemdoTheme.secondaryInk)
                            Text(workout.notes)
                                .font(.subheadline)
                                .foregroundStyle(MemdoTheme.ink)
                        }
                        .padding(MemdoMetrics.pagePadding)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(MemdoPageBackground())
            .navigationTitle(workout.activityType.label)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("편집") { editing = true }
                }
            }
            .sheet(isPresented: $editing) {
                WorkoutLogEditorSheet(workout: workout)
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
        let stats: [(String, String, String)] = [
            ("시간",   workout.durationFormatted, "timer"),
            workout.distanceFormatted.map { ("거리", $0, "arrow.triangle.swap") },
            workout.paceFormatted.map { ("페이스", $0, "speedometer") },
            workout.calories.map { ("칼로리", "\(Int($0))kcal", "flame") },
            workout.avgHeartRate.map { ("평균 심박수", "\(Int($0))bpm", "heart") },
            workout.locationName.map { ("장소", $0, "mappin") }
        ].compactMap { $0 }

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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MemdoTheme.secondaryInk)
                .padding(.horizontal, MemdoMetrics.pagePadding)
            VStack(spacing: 0) {
                ForEach(exercises) { set in
                    HStack {
                        Text(set.name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(set.summary).font(.subheadline).foregroundStyle(MemdoTheme.secondaryInk)
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
                .font(.caption.weight(.medium))
                .foregroundStyle(MemdoTheme.secondaryInk)
            Text(value)
                .font(.subheadline.weight(.semibold))
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

    @State private var draft: WorkoutLog
    @State private var photoPicker: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isUploading = false

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
            Form {
                Section("종류") {
                    Picker("활동", selection: $draft.activityType) {
                        ForEach(WorkoutActivityType.allCases) { type in
                            Label(type.label, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("시간") {
                    DatePicker("시작", selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("종료", selection: $draft.endedAt,   displayedComponents: [.date, .hourAndMinute])
                }

                Section("수치") {
                    TextField("거리 (km)", value: Binding(
                        get: { draft.distanceMeters.map { $0 / 1000 } ?? 0 },
                        set: { draft.distanceMeters = $0 > 0 ? $0 * 1000 : nil }
                    ), format: .number)
                    .keyboardType(.decimalPad)

                    TextField("칼로리 (kcal)", value: $draft.calories, format: .number)
                        .keyboardType(.decimalPad)
                }

                Section("장소") {
                    TextField("헬스장 이름 또는 장소", text: Binding(
                        get: { draft.locationName ?? "" },
                        set: { draft.locationName = $0.isEmpty ? nil : $0 }
                    ))
                }

                Section("사진 첨부 (Nike RC 캡처 등)") {
                    PhotosPicker(selection: $photoPicker, matching: .images) {
                        Label(draft.photoURL != nil ? "사진 변경" : "사진 선택", systemImage: "photo.badge.plus")
                    }
                    .onChange(of: photoPicker) { _, item in
                        Task {
                            photoData = try? await item?.loadTransferable(type: Data.self)
                        }
                    }
                    if let data = photoData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable().scaledToFill()
                            .frame(height: 160).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // 근력 운동 세트 기록
                if draft.activityType == .strengthTraining {
                    exerciseSection
                }

                Section("노트") {
                    TextField("메모", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isNew ? "운동 기록 추가" : "운동 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(isUploading)
                }
            }
            .overlay {
                if isUploading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial) }
            }
        }
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
                HStack {
                    TextField("운동 이름", text: $set.name)
                    Spacer()
                    TextField("세트", value: $set.sets, format: .number)
                        .frame(width: 36).multilineTextAlignment(.center)
                    Text("세트")
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }
            .onDelete { exercisesBinding.wrappedValue.remove(atOffsets: $0) }
            Button("세트 추가") {
                var sets = draft.exercises ?? []
                sets.append(ExerciseSet(name: "", sets: 3, reps: 10))
                draft.exercises = sets
            }
        } header: {
            Text("세트 기록")
        }
    }

    private func save() {
        draft.durationSeconds = max(1, Int(draft.endedAt.timeIntervalSince(draft.startedAt)))
        Task {
            isUploading = true
            defer { isUploading = false }

            // 첨부 사진 업로드는 WorkoutStore가 내부적으로 처리
            // photoData는 WorkoutStore에 함께 전달 (현재는 메모만 저장)
            // TODO: photo upload integration after backend deploy
            if isNew {
                workoutStore.save(draft)
            } else {
                workoutStore.update(draft)
            }
            dismiss()
        }
    }
}

// MARK: - HealthKit Import Sheet

struct HealthKitImportSheet: View {
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var pending: [WorkoutLog] = []
    @State private var selected: Set<UUID> = []
    @State private var phase: ImportPhase = .loading

    enum ImportPhase { case loading, empty, ready, importing }

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
                    .font(.subheadline)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                                                     ? MemdoTheme.brand : MemdoTheme.secondaryInk)
                                    .font(.title3)
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
                    .font(.footnote)
                }
            }
        }
    }

    private func importRow(_ workout: WorkoutLog) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(activityColor(workout.activityType).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: workout.activityType.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(activityColor(workout.activityType))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityType.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MemdoTheme.ink)
                HStack(spacing: 6) {
                    Text(workout.startedAt.formatted(.dateTime.month().day().hour().minute()))
                    if let d = workout.distanceFormatted {
                        Text("·"); Text(d)
                    }
                    Text("·"); Text(workout.durationFormatted)
                }
                .font(.caption)
                .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
    }

    private func activityColor(_ type: WorkoutActivityType) -> Color {
        switch type {
        case .running: .orange
        case .cycling: .green
        case .swimming: .blue
        case .strengthTraining: .purple
        case .yoga: .teal
        case .hiit: .red
        case .walking: .mint
        case .other: MemdoTheme.brand
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
        dismiss()
    }
}
