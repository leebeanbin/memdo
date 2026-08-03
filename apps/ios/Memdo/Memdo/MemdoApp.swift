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
                VStack(spacing: 16) {
                    MemdoBrandMark(size: 44)
                    ProgressView("세션을 확인하는 중")
                }
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
    @Environment(\.colorScheme) private var colorScheme

    let session: MemdoSession

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MemdoPageBackground().ignoresSafeArea()

                ViewThatFits(in: .vertical) {
                    signInContent
                        .frame(minHeight: proxy.size.height - 48)

                    ScrollView {
                        signInContent
                            .frame(minHeight: proxy.size.height - 48)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.horizontal, MemdoMetrics.pagePadding)
                .padding(.vertical, 24)
            }
        }
        .disabled(session.isBusy)
    }

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MemdoBrandMark(size: 26)
                Text("Memdo")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 56)

            VStack(alignment: .leading, spacing: 12) {
                Text("내 하루를,\n내 방식대로.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .tracking(-0.4)
                    .accessibilityAddTraits(.isHeader)
                Text("일정은 선명하게, Agent는 조용하게.")
                    .font(.subheadline)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }

            Spacer(minLength: 64)

            VStack(spacing: 12) {
                providerButton("Google로 계속", image: "GoogleSignIn", provider: .google)
                providerButton("GitHub로 계속", image: "GitHubSignIn", provider: .github)
            }

            VStack(alignment: .leading, spacing: 12) {
                if session.isBusy {
                    ProgressView("로그인 화면을 여는 중")
                        .font(.caption)
                }

                if let errorMessage = session.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("로그인 오류: \(errorMessage)")
                }

                Text("계정 정보는 로그인과 일정 동기화에만 사용됩니다. 캘린더 권한은 연결할 때 별도로 요청합니다.")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func providerButton(_ title: String, image: String, provider: Provider) -> some View {
        Button {
            Task { await session.signIn(with: provider) }
        } label: {
            HStack(spacing: 12) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
            }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(providerBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(providerOutline)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MemdoTheme.ink)
    }

    private var providerBackground: Color {
        colorScheme == .dark ? Color(red: 19 / 255, green: 19 / 255, blue: 20 / 255) : .white
    }

    private var providerOutline: Color {
        colorScheme == .dark
            ? Color(red: 142 / 255, green: 145 / 255, blue: 143 / 255)
            : Color(red: 116 / 255, green: 119 / 255, blue: 117 / 255)
    }
}
