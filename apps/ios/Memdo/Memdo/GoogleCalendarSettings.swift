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
    @State private var status: GoogleCalendarStatusResponseDTO?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var authSession: ASWebAuthenticationSession?
    private let presentationContext = GoogleCalendarAuthPresentationContext()

    private var isConnected: Bool { status?.connected == true }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MCPToolIdentityRow(
                        icon: .asset("GoogleCalendar"),
                        title: "Google Calendar",
                        summary: "Google Calendar 일정을 가져와서 내 캘린더에 함께 보여줘요."
                    )
                } header: {
                    Text("Agent MCP 도구")
                }
                Section("연결하면 가능한 일") {
                    Label("Google Calendar 일정을 캘린더 화면에 함께 표시", systemImage: "calendar")
                    Label("15분마다 자동으로 최신 일정 반영", systemImage: "arrow.triangle.2.circlepath")
                }
                Section("권한 원칙") {
                    Label("읽기 전용 — Google Calendar에 쓰거나 수정하지 않음", systemImage: "eye")
                }
                if isConnected {
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
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
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
        .task { await loadStatus() }
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
        errorMessage = nil
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
                    errorMessage = "연결이 취소되었어요."
                    return
                }
                await loadStatus()
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                errorMessage = "연결하지 못했어요. 잠시 후 다시 시도해 주세요."
            }
        }
    }

    private func disconnect() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await scheduleStore.googleCalendarDisconnect()
                await loadStatus()
            } catch {
                errorMessage = "연결 해지에 실패했어요. 잠시 후 다시 시도해 주세요."
            }
        }
    }
}
