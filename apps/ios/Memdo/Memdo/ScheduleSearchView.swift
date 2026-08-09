import SwiftUI

struct ScheduleSearchView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Binding var query: String
    let scope: ScheduleSearchScope
    @State private var status = "전체 상태"
    @State private var period = "전체 기간"
    @State private var presentedSheet: SearchSheet?
    @State private var results: [ScheduleDetail] = []
    @State private var searchError: String?
    @State private var isSearching = false

    private var activeFilterDescription: String? {
        let filters = [status, period].filter { $0 != "전체 상태" && $0 != "전체 기간" }
        return filters.isEmpty ? nil : filters.joined(separator: " · ")
    }

    private var periodInterval: DateInterval? {
        let calendar = Calendar.current
        let now = Date.now
        switch period {
        case "이번 주":
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case "최근 2주":
            let today = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -13, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
            return DateInterval(start: start, end: end)
        default:
            return nil
        }
    }

    // Text matching now happens server-side (`/search`); the remaining scope/
    // status/period controls filter the returned matches client-side.
    private var filteredResults: [ScheduleDetail] {
        let interval = periodInterval
        return results.filter { schedule in
            let matchesScope = scope == .all || (scope == .google ? schedule.isExternal : !schedule.isExternal)
            let matchesStatus = status == "전체 상태" || (status == "완료" ? schedule.isDone : !schedule.isDone)
            let matchesPeriod = interval.map {
                schedule.scheduledDate >= $0.start && schedule.scheduledDate < $0.end
            } ?? true
            return schedule.isActive && matchesScope && matchesStatus && matchesPeriod
        }
        .sorted { ($0.scheduledDate, $0.timeSortKey) > ($1.scheduledDate, $1.timeSortKey) }
    }

    var body: some View {
        SearchResultsSection(
            schedules: filteredResults,
            filterDescription: activeFilterDescription,
            searchError: searchError,
            isSearching: isSearching,
            onOpenFilters: { presentedSheet = .filters },
            onOpenSchedule: { presentedSheet = .detail($0) }
        )
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .detail(let schedule):
                ScheduleDetailSheet(schedule: schedule, onSave: scheduleStore.save)
            case .filters:
                SearchFilterSheet(status: $status, period: $period)
            }
        }
        .task(id: query) {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else {
                results = []
                searchError = nil
                isSearching = false
                return
            }
            isSearching = true
            // Debounce keystrokes; `.task(id:)` cancels the prior run on each change.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                results = try await scheduleStore.search(term)
                searchError = nil
            } catch {
                results = []
                searchError = error.localizedDescription
            }
            isSearching = false
        }
    }
}

enum ScheduleSearchScope: String, CaseIterable, Identifiable {
    case all
    case mine
    case google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .mine: "내 일정"
        case .google: "Google"
        }
    }
}

private struct SearchResultsSection: View {
    let schedules: [ScheduleDetail]
    let filterDescription: String?
    let searchError: String?
    let isSearching: Bool
    let onOpenFilters: () -> Void
    let onOpenSchedule: (ScheduleDetail) -> Void

    var body: some View {
        MemdoSection(
            title: "검색 결과",
            trailing: "\(schedules.count)개",
            actionIcon: "line.3.horizontal.decrease",
            actionLabel: "상세 필터",
            action: onOpenFilters
        ) {
            if let filterDescription {
                Text(filterDescription)
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            if isSearching {
                HStack(spacing: MemdoMetrics.rowSpacing) {
                    ProgressView()
                        .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                    Text("검색 중")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, MemdoMetrics.rowInset)
                .memdoRowGroup()
            } else if let searchError {
                MemdoStatusRow(
                    title: "검색을 완료하지 못했어요",
                    systemImage: "exclamationmark.triangle",
                    detail: searchError,
                    tint: MemdoTheme.brand
                )
            } else if schedules.isEmpty {
                MemdoStatusRow(
                    title: "검색 결과가 없어요",
                    systemImage: "magnifyingglass",
                    detail: "검색어 또는 필터를 바꿔보세요."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(schedules) { schedule in
                        ScheduleRow(
                            schedule: schedule,
                            context: .dated,
                            onOpen: { onOpenSchedule(schedule) }
                        )
                        if schedule.id != schedules.last?.id {
                            Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                        }
                    }
                }
                .memdoRowGroup()
            }
        }
    }
}

private enum SearchSheet: Identifiable {
    case detail(ScheduleDetail)
    case filters

    var id: String {
        switch self {
        case .detail(let schedule): "detail-\(schedule.id)"
        case .filters: "filters"
        }
    }
}

private struct SearchFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var status: String
    @Binding var period: String

    var body: some View {
        NavigationStack {
            Form {
                Picker("상태", selection: $status) {
                    ForEach(["전체 상태", "예정", "완료"], id: \.self) { Text($0) }
                }
                Picker("기간", selection: $period) {
                    ForEach(["전체 기간", "최근 2주", "이번 주"], id: \.self) { Text($0) }
                }
                Button("필터 초기화", action: resetFilters)
            }
            .memdoSystemList()
            .navigationTitle("상세 필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("적용") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .memdoSheetPresentation([.medium])
    }

    private func resetFilters() {
        status = "전체 상태"
        period = "전체 기간"
    }
}
