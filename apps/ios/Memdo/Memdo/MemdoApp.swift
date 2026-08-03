import AuthenticationServices
import Observation
import Supabase
import SwiftUI

@main
struct MemdoApp: App {
    @State private var session = MemdoSession()

    var body: some Scene {
        WindowGroup {
            MemdoRootView(session: session)
                .environment(session)
                .onOpenURL { session.handle($0) }
                .task { await session.observe() }
        }
    }
}

@MainActor
@Observable
final class MemdoSession {
    enum Phase: Equatable {
        case loading
        case signedOut
        case signedIn
        case failed(String)
    }

    private(set) var phase = Phase.loading
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var accountLabel = ""
    let scheduleStore: ScheduleStore?

    private let client: SupabaseClient?
    private var activeUserID: UUID?

    init() {
        do {
            let configuration = try MemdoConfiguration.current()
            let client = SupabaseClient(
                supabaseURL: configuration.projectURL,
                supabaseKey: configuration.publishableKey
            )
            self.client = client
            scheduleStore = ScheduleStore(
                repository: ScheduleRepository(configuration: configuration, auth: client)
            )
        } catch {
            client = nil
            scheduleStore = nil
            phase = .failed(error.localizedDescription)
        }
    }

    func observe() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            if let session {
                if activeUserID != session.user.id {
                    scheduleStore?.reset()
                }
                activeUserID = session.user.id
                accountLabel = session.user.isAnonymous ? "게스트" : session.user.email ?? "연결된 계정"
                phase = .signedIn
            } else {
                activeUserID = nil
                accountLabel = ""
                scheduleStore?.reset()
                phase = .signedOut
            }
        }
    }

    func signIn(with provider: Provider) async {
        guard let client, let redirectURL = URL(string: "memdo://auth/callback") else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await client.auth.signInWithOAuth(provider: provider, redirectTo: redirectURL)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func continueAsGuest() async {
        guard let client else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await client.auth.signInAnonymously()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard let client else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handle(_ url: URL) {
        guard url.scheme == "memdo", url.host == "auth" else { return }
        client?.handle(url)
    }
}

private struct MemdoRootView: View {
    let session: MemdoSession

    var body: some View {
        switch session.phase {
        case .loading:
            ZStack {
                MemdoPageBackground().ignoresSafeArea()
                ProgressView("세션을 확인하는 중")
            }
        case .signedOut:
            MemdoSignInView(session: session)
        case .signedIn:
            if let scheduleStore = session.scheduleStore {
                AppShellView(scheduleStore: scheduleStore)
            }
        case .failed(let message):
            ContentUnavailableView(
                "앱 설정을 확인해 주세요",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }
}

private struct MemdoSignInView: View {
    let session: MemdoSession

    var body: some View {
        ZStack {
            MemdoPageBackground().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .memdoFloatingSurface(radius: 16)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Memdo")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("내 일정은 선명하게, Agent는 조용하게.")
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                VStack(spacing: 10) {
                    providerButton("Google로 계속", systemImage: "g.circle", provider: .google)
                    providerButton("GitHub로 계속", systemImage: "chevron.left.forwardslash.chevron.right", provider: .github)

                    Button("계정 없이 시작") {
                        Task { await session.continueAsGuest() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .frame(minHeight: MemdoMetrics.touchTarget)
                }

                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("로그인 오류: \(errorMessage)")
                }
            }
            .padding(MemdoMetrics.pagePadding)
            .padding(.bottom, 24)
        }
        .disabled(session.isBusy)
        .overlay {
            if session.isBusy {
                ProgressView()
                    .padding(18)
                    .memdoFloatingSurface(radius: 20)
            }
        }
    }

    private func providerButton(_ title: String, systemImage: String, provider: Provider) -> some View {
        Button {
            Task { await session.signIn(with: provider) }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MemdoTheme.controlOutline)
                }
        }
        .buttonStyle(.plain)
    }
}
