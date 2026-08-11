import SwiftUI

struct ShareWorkoutView: View {
    @State private var activityType = "running"
    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var notes: String

    let onSave: (PendingWorkout) -> Void
    let onCancel: () -> Void

    private static let activities: [(id: String, label: String, icon: String)] = [
        ("running",          "러닝",      "figure.run"),
        ("walking",          "걷기",      "figure.walk"),
        ("cycling",          "사이클",    "figure.outdoor.cycle"),
        ("swimming",         "수영",      "figure.pool.swim"),
        ("strength_training","근력 운동", "dumbbell"),
        ("yoga",             "요가",      "figure.yoga"),
        ("hiit",             "HIIT",      "figure.highintensity.intervaltraining"),
        ("other",            "기타 운동", "figure.mixed.cardio"),
    ]

    init(
        initialNotes: String,
        onSave: @escaping (PendingWorkout) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let now = Date.now
        _startedAt = State(initialValue: now.addingTimeInterval(-1800))
        _endedAt   = State(initialValue: now)
        _notes     = State(initialValue: initialNotes)
        self.onSave   = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("활동 종류", selection: $activityType) {
                        ForEach(Self.activities, id: \.id) { a in
                            Label(a.label, systemImage: a.icon).tag(a.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    DatePicker("시작", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("종료", selection: $endedAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])
                }

                if !notes.isEmpty {
                    Section("공유된 내용") {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    }
                }
            }
            .navigationTitle("운동 기록 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(PendingWorkout(
                            activityType: activityType,
                            startedAt: startedAt,
                            endedAt: endedAt,
                            notes: notes,
                            sourceText: notes.isEmpty ? nil : notes
                        ))
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
