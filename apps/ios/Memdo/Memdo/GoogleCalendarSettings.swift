import AuthenticationServices
import SwiftUI

@MainActor
private final class GoogleCalendarAuthPresentationContext: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

struct GoogleCalendarConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(AppNoticeCenter.self) private var noticeCenter
    @State private var status: GoogleCalendarStatusResponseDTO?
    @State private var isBusy = false
    @State private var authSession: ASWebAuthenticationSession?
    @State private var showSyncedCalendars = false
    private let presentationContext = GoogleCalendarAuthPresentationContext()

    private var isConnected: Bool { status?.connected == true }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MCPToolIdentityRow(
                        icon: .asset("GoogleCalendar"),
                        title: "Google Calendar",
                        summary: "Memdo와 Google Calendar 일정을 서로 동기화해요."
                    )
                } header: {
                    Text("Agent MCP 도구")
                }
                Section("연결하면 가능한 일") {
                    Label("Google Calendar 일정을 캘린더 화면에 함께 표시", systemImage: "calendar")
                    Label("Google Calendar 변경사항을 실시간에 가깝게 반영 (최대 15분 지연 가능)", systemImage: "arrow.triangle.2.circlepath")
                    Label("Memdo에서 만들거나 수정한 일정을 Google Calendar에 반영", systemImage: "arrow.up.circle")
                    Label("Google Calendar에서 가져온 일정도 Memdo에서 수정 가능", systemImage: "pencil.circle")
                }
                Section("권한 원칙") {
                    Label("양방향 동기화 — 서로 만들거나 수정한 일정이 상대방에도 반영돼요", systemImage: "arrow.triangle.2.circlepath.circle")
                }
                if isConnected {
                    Section {
                        Button {
                            showSyncedCalendars = true
                        } label: {
                            Label("다른 캘린더 추가", systemImage: "calendar.badge.plus")
                        }
                    } footer: {
                        Text("공휴일 캘린더처럼 기본 캘린더 외에 구독 중인 Google 캘린더를 더 가져올 수 있어요.")
                    }
                    Section {
                        if let lastSyncedAt = status?.lastSyncedAt {
                            LabeledContent("마지막 동기화", value: lastSyncedAt)
                        }
                        Button(role: .destructive, action: disconnect) {
                            if isBusy {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("연결 해제 중")
                                }
                            } else {
                                Text("연결 해지")
                            }
                        }
                            .disabled(isBusy)
                    }
                } else {
                    Section {
                        Button(action: connect) {
                            if isBusy {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("연결 중")
                                }
                            } else {
                                Text("Google Calendar 연결")
                            }
                        }
                            .disabled(isBusy)
                    }
                }
                if noticeCenter.current != nil {
                    Section {
                        AppNoticeInlineLabel()
                    }
                }
            }
            .memdoSystemList()
            .navigationTitle("Google Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
        .appNoticeToast()
        .task { await loadStatus() }
        .sheet(isPresented: $showSyncedCalendars) {
            GoogleSyncedCalendarsPickerSheet()
        }
    }

    private func loadStatus() async {
        do {
            status = try await scheduleStore.googleCalendarStatus()
        } catch {
            // Silent: an unknown connection state just shows the "연결" button,
            // which re-checks on the next action anyway.
        }
    }

    private func connect() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let authorizationURL = try await scheduleStore.googleCalendarStart()
                let callbackURL = try await withCheckedThrowingContinuation { (
                    continuation: CheckedContinuation<URL, Error>
                ) in
                    let session = ASWebAuthenticationSession(
                        url: authorizationURL,
                        callbackURLScheme: "memdo"
                    ) { url, error in
                        if let url {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(
                                throwing: error ?? ScheduleAPIError.invalidResponse
                            )
                        }
                    }
                    session.presentationContextProvider = presentationContext
                    session.prefersEphemeralWebBrowserSession = true
                    authSession = session
                    session.start()
                }
                let statusValue = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "status" })?.value
                if statusValue != "success" {
                    noticeCenter.error("연결이 취소되었어요.")
                    return
                }
                await loadStatus()
                noticeCenter.success("Google Calendar를 연결했어요.")
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                noticeCenter.error("연결하지 못했어요. 잠시 후 다시 시도해 주세요.")
            }
        }
    }

    private func disconnect() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await scheduleStore.googleCalendarDisconnect()
                await loadStatus()
                noticeCenter.success("연결을 해지했어요.")
            } catch {
                noticeCenter.error("연결 해지에 실패했어요. 잠시 후 다시 시도해 주세요.")
            }
        }
    }
}

// MARK: - Additional synced calendars (holidays, a secondary calendar, ...)

/// Google's own "다른 캘린더" list, toggle-able -- the primary calendar
/// itself isn't shown here (connect/disconnect on the sheet above manages
/// that); each additional calendar picked up here gets its own synthetic
/// entry in Calendar Management (name/color), same as the primary one
/// already does.
struct GoogleSyncedCalendarsPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(AppNoticeCenter.self) private var noticeCenter
    @State private var available: [GoogleAvailableCalendarDTO] = []
    // Tracked separately from `available`'s own isSynced snapshot so a
    // toggle can update immediately without re-fetching the whole list.
    @State private var syncedIds: Set<String> = []
    @State private var syncedRowIdsByCalendarId: [String: String] = [:]
    @State private var isLoading = true
    @State private var busyCalendarId: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if available.isEmpty {
                    MemdoStatusRow(
                        title: "추가할 수 있는 캘린더가 없어요",
                        systemImage: "calendar",
                        detail: "Google Calendar에 구독 중인 다른 캘린더가 없는 것 같아요."
                    )
                } else {
                    List {
                        Section {
                            ForEach(available) { calendar in
                                Toggle(isOn: bindingFor(calendar)) {
                                    Text(calendar.summary)
                                }
                                .disabled(busyCalendarId == calendar.googleCalendarId)
                            }
                        } footer: {
                            Text("공휴일 캘린더처럼 Google Calendar에서 구독 중인 캘린더예요. 켜면 일정을 가져오기 시작해요 (최대 15분 정도 걸릴 수 있어요).")
                        }
                        if noticeCenter.current != nil {
                            Section {
                                AppNoticeInlineLabel()
                            }
                        }
                    }
                    .memdoSystemList()
                }
            }
            .navigationTitle("다른 캘린더 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
        .appNoticeToast()
        .task { await load() }
    }

    private func bindingFor(_ calendar: GoogleAvailableCalendarDTO) -> Binding<Bool> {
        Binding(
            get: { syncedIds.contains(calendar.googleCalendarId) },
            set: { newValue in toggle(calendar, isOn: newValue) }
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await scheduleStore.googleSyncedCalendars()
            available = response.available
            syncedIds = Set(response.synced.map(\.googleCalendarId))
            syncedRowIdsByCalendarId = Dictionary(
                uniqueKeysWithValues: response.synced.map { ($0.googleCalendarId, $0.id) }
            )
        } catch {
            noticeCenter.error("캘린더 목록을 불러오지 못했어요.")
        }
    }

    private func toggle(_ calendar: GoogleAvailableCalendarDTO, isOn: Bool) {
        busyCalendarId = calendar.googleCalendarId
        Task {
            defer { busyCalendarId = nil }
            do {
                if isOn {
                    try await scheduleStore.addGoogleSyncedCalendar(
                        googleCalendarId: calendar.googleCalendarId,
                        summary: calendar.summary
                    )
                } else if let rowId = syncedRowIdsByCalendarId[calendar.googleCalendarId] {
                    try await scheduleStore.removeGoogleSyncedCalendar(id: rowId)
                }
                await load()
                await scheduleStore.refreshCalendars()
            } catch {
                noticeCenter.error(isOn ? "캘린더를 추가하지 못했어요." : "캘린더를 제거하지 못했어요.")
            }
        }
    }
}
