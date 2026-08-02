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
        VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
            SearchFilterBar(
                scope: scope,
                filterDescription: activeFilterDescription,
                onOpenFilters: { presentedSheet = .filters }
            )
            SearchResultsSection(
                query: query,
                schedules: filteredResults,
                onOpenSchedule: { presentedSheet = .detail($0) }
            )
        }
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

private struct SearchFilterBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let scope: ScheduleSearchScope
    let filterDescription: String?
    let onOpenFilters: () -> Void

    var body: some View {
        filterLayout {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(scope.title)에서 검색 중")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MemdoTheme.ink)
                Text(filterDescription ?? "완료 상태와 기간을 더 좁힐 수 있어요")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onOpenFilters) {
                MemdoIconButtonLabel(systemImage: "line.3.horizontal.decrease")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("상세 필터")
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var filterLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }
}

private struct SearchResultsSection: View {
    let query: String
    let schedules: [ScheduleDetail]
    let onOpenSchedule: (ScheduleDetail) -> Void

    var body: some View {
        MemdoSection(title: "검색 결과", trailing: "\(schedules.count)개") {
            if schedules.isEmpty {
                ContentUnavailableView(
                    "검색 결과가 없어요",
                    systemImage: "magnifyingglass",
                    description: Text("검색어를 바꾸거나 상세 필터를 초기화해 보세요.")
                )
                    .frame(maxWidth: .infinity, minHeight: 160)
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
                .memdoCard()
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
            .scrollContentBackground(.hidden)
            .background(MemdoTheme.background)
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
