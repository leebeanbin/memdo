import SwiftUI

// MARK: - Calendar Management (bd26)
//
// Calendars were GET-only before this -- every user was stuck with the 2
// seeded at signup (개인/업무). This screen covers create/rename/recolor/
// show-hide/delete for purpose:'custom' calendars; 개인/업무 can be
// renamed/recolored here too but never deleted (matches the backend's own
// purpose-based restriction).

struct CalendarManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var items: [CalendarResponseDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddCalendar = false
    @State private var editingCalendar: CalendarResponseDTO?
    @State private var deletingCalendar: CalendarResponseDTO?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let errorMessage {
                            Section {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(MemdoTypography.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        Section {
                            ForEach(items) { item in
                                Button {
                                    editingCalendar = item
                                } label: {
                                    CalendarManagementRow(item: item)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    if item.purpose == "custom" {
                                        Button("삭제", role: .destructive) {
                                            deletingCalendar = item
                                        }
                                    }
                                }
                            }
                        } footer: {
                            Text("개인·업무 캘린더는 이름과 색상만 바꿀 수 있어요. 직접 추가한 캘린더는 일정이 없을 때만 삭제할 수 있어요.")
                        }
                    }
                    .memdoSystemList()
                }
            }
            .navigationTitle("캘린더 관리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddCalendar = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAddCalendar) {
            CalendarEditSheet(existing: nil) { name, colorToken in
                await create(name: name, colorToken: colorToken)
            }
        }
        .sheet(item: $editingCalendar) { calendar in
            CalendarEditSheet(existing: calendar) { name, colorToken in
                await update(calendar, name: name, colorToken: colorToken)
            }
        }
        .alert(
            "캘린더를 삭제할까요?",
            isPresented: Binding(
                get: { deletingCalendar != nil },
                set: { if !$0 { deletingCalendar = nil } }
            )
        ) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                if let calendar = deletingCalendar {
                    Task { await delete(calendar) }
                }
            }
        } message: {
            Text("이 작업은 되돌릴 수 없어요.")
        }
        .memdoSheetPresentation([.large])
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await scheduleStore.loadCalendarDTOs()
            errorMessage = nil
        } catch {
            errorMessage = "캘린더를 불러오지 못했어요."
        }
    }

    private func create(name: String, colorToken: String?) async {
        do {
            try await scheduleStore.createCalendar(
                name: name,
                colorToken: colorToken,
                sortOrder: items.count
            )
            await load()
            await scheduleStore.refreshCalendars()
        } catch {
            errorMessage = "캘린더를 추가하지 못했어요."
        }
    }

    private func update(_ calendar: CalendarResponseDTO, name: String, colorToken: String?) async {
        do {
            try await scheduleStore.updateCalendar(
                id: calendar.id,
                name: name,
                colorToken: colorToken,
                sortOrder: calendar.sortOrder,
                isVisible: calendar.isVisible
            )
            await load()
            await scheduleStore.refreshCalendars()
        } catch {
            errorMessage = "캘린더를 수정하지 못했어요."
        }
    }

    private func delete(_ calendar: CalendarResponseDTO) async {
        do {
            try await scheduleStore.deleteCalendar(id: calendar.id)
            await load()
            await scheduleStore.refreshCalendars()
        } catch ScheduleAPIError.server(_, _, let message, _) {
            errorMessage = message
        } catch {
            errorMessage = "캘린더를 삭제하지 못했어요."
        }
    }
}

private struct CalendarManagementRow: View {
    let item: CalendarResponseDTO

    private var color: ScheduleColor? {
        item.colorToken.flatMap(ScheduleColor.init(rawValue:))
    }

    private var purposeLabel: String {
        switch item.purpose {
        case "personal": "개인"
        case "work": "업무"
        default: "직접 추가"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color?.swiftUIColor ?? MemdoTheme.controlOutline)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.ink)
                Text(purposeLabel + (item.isVisible ? "" : " · 숨김"))
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Add/Edit Sheet

private struct CalendarEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existing: CalendarResponseDTO?
    let onSave: (String, String?) async -> Void

    @State private var name: String
    @State private var selectedColor: ScheduleColor?
    @State private var isSaving = false

    init(existing: CalendarResponseDTO?, onSave: @escaping (String, String?) async -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _selectedColor = State(initialValue: existing?.colorToken.flatMap(ScheduleColor.init(rawValue:)))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("이름") {
                    TextField("캘린더 이름", text: $name)
                }
                Section("색상") {
                    HStack(spacing: 10) {
                        ForEach(ScheduleColor.allCases) { c in
                            MemdoColorSwatch(color: c, isSelected: selectedColor == c) {
                                selectedColor = selectedColor == c ? nil : c
                            }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "캘린더 추가" : "캘린더 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        isSaving = true
                        Task {
                            await onSave(
                                name.trimmingCharacters(in: .whitespacesAndNewlines),
                                selectedColor?.rawValue
                            )
                            dismiss()
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .memdoSheetPresentation([.medium])
    }
}
