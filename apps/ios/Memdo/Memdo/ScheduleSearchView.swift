import SwiftUI

struct ScheduleSearchView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Binding var query: String
    let scope: ScheduleSearchScope
    @State private var status = "전체 상태"
    @State private var period = "전체 기간"
    @State private var presentedSheet: SearchSheet?

    private var activeFilterDescription: String? {
        let filters = [status, period].filter { $0 != "전체 상태" && $0 != "전체 기간" }
        return filters.isEmpty ? nil : filters.joined(separator: " · ")
    }

    private var filteredResults: [ScheduleDetail] {
        scheduleStore.schedules.filter {
            ($0.title.localizedCaseInsensitiveContains(query) ||
             $0.memo.localizedCaseInsensitiveContains(query) ||
             $0.location.localizedCaseInsensitiveContains(query)) &&
            (scope == .all || (scope == .google ? $0.isExternal : !$0.isExternal)) &&
            (status == "전체 상태" || (status == "완료" ? $0.isDone : !$0.isDone)) &&
            (period == "전체 기간" || (period == "이번 주" ? $0.day >= 27 : $0.day >= 18))
        }
        .sorted { ($0.day, $0.timeSortKey) > ($1.day, $1.timeSortKey) }
    }

    var body: some View {
        SearchResultsSection(
            schedules: filteredResults,
            filterDescription: activeFilterDescription,
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
            if schedules.isEmpty {
                ContentUnavailableView(
                    "검색 결과가 없어요",
                    systemImage: "magnifyingglass",
                    description: Text("검색어 또는 필터를 바꿔보세요.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
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
