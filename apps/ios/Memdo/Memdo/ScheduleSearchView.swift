import SwiftUI

private enum SearchStatus: String, CaseIterable, Identifiable {
    case all = "전체 상태"
    case pending = "예정"
    case done = "완료"
    var id: String { rawValue }
}

private enum SearchPeriod: String, CaseIterable, Identifiable {
    case all = "전체 기간"
    case twoWeeks = "최근 2주"
    case thisWeek = "이번 주"
    var id: String { rawValue }

    var interval: DateInterval? {
        let calendar = Calendar.current
        let now = Date.now
        switch self {
        case .all: return nil
        case .thisWeek: return calendar.dateInterval(of: .weekOfYear, for: now)
        case .twoWeeks:
            let today = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -13, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
            return DateInterval(start: start, end: end)
        }
    }
}

struct ScheduleSearchView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Binding var query: String
    let scope: ScheduleSearchScope
    @State private var status = SearchStatus.all
    @State private var period = SearchPeriod.all
    @State private var presentedSheet: SearchSheet?
    @State private var results: [ScheduleDetail] = []
    @State private var searchError: String?
    @State private var isSearching = false

    private var activeFilterDescription: String? {
        let parts = [
            status != .all ? status.rawValue : nil,
            period != .all ? period.rawValue : nil
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // Text matching now happens server-side (`/search`); the remaining scope/
    // status/period controls filter the returned matches client-side.
    private var filteredResults: [ScheduleDetail] {
        let interval = period.interval
        return results.filter { schedule in
            let matchesScope = scope == .all || (scope == .google ? schedule.isExternal : !schedule.isExternal)
            let matchesStatus: Bool
            switch status {
            case .all: matchesStatus = true
            case .pending: matchesStatus = !schedule.isDone
            case .done: matchesStatus = schedule.isDone
            }
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
                ScheduleDetailSheet(schedule: schedule, onSave: { edited in Task { try? await scheduleStore.save(edited) } })
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
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            if isSearching {
                HStack(spacing: MemdoMetrics.rowSpacing) {
                    ProgressView()
                        .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                    Text("검색 중")
                        .font(MemdoTypography.action)
                }
                .padding(.horizontal, MemdoMetrics.rowInset)
                .memdoRowGroup()
            } else if let searchError {
                MemdoStatusRow(
                    title: "검색을 완료하지 못했어요",
                    systemImage: "exclamationmark.triangle",
                    detail: searchError,
                    tint: MemdoTheme.brandInk
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
    @Binding var status: SearchStatus
    @Binding var period: SearchPeriod

    var body: some View {
        NavigationStack {
            Form {
                Picker("상태", selection: $status) {
                    ForEach(SearchStatus.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("기간", selection: $period) {
                    ForEach(SearchPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                Button("필터 초기화", action: resetFilters)
            }
            .memdoSystemList()
            .navigationTitle("상세 필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .memdoSheetPresentation([.medium])
    }

    private func resetFilters() {
        status = .all
        period = .all
    }
}
