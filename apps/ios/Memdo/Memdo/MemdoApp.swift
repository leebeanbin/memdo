import AuthenticationServices
import CryptoKit
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
    let preferencesStore: PreferencesStore?

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
            preferencesStore = PreferencesStore(
                repository: PreferencesRepository(configuration: configuration, auth: client)
            )
        } catch {
            client = nil
            scheduleStore = nil
            preferencesStore = nil
            phase = .failed(error.localizedDescription)
        }
    }

    func observe() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            if let session {
                if activeUserID != session.user.id {
                    scheduleStore?.reset()
                    preferencesStore?.reset()
                }
                activeUserID = session.user.id
                accountLabel = session.user.isAnonymous ? "게스트" : session.user.email ?? "연결된 계정"
                phase = .signedIn
            } else {
                activeUserID = nil
                accountLabel = ""
                scheduleStore?.reset()
                preferencesStore?.reset()
                await startAnonymousSession()
            }
        }
    }

    /// Anonymous-first entry: no login wall. On a missing session we silently
    /// create an anonymous one so the app opens straight to the main screen;
    /// accounts are connected later. Only a hard failure falls back to sign-in.
    private func startAnonymousSession() async {
        guard let client else { return }
        do {
            try await client.auth.signInAnonymously()
            // Success emits a new auth state change carrying the session.
        } catch {
            phase = .signedOut
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

    func signInWithApple(idToken: String, nonce: String) async {
        guard let client else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsLaunchBrand = true

    let session: MemdoSession

    var body: some View {
        ZStack {
            if showsLaunchBrand {
                MemdoLaunchView()
                    .transition(.opacity)
            } else {
                sessionContent
                    .transition(.opacity)
            }
        }
        .task {
            guard showsLaunchBrand else { return }
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                showsLaunchBrand = false
            }
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch session.phase {
        case .loading:
            MemdoLaunchView()
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

private struct MemdoLaunchView: View {
    var body: some View {
        ZStack {
            MemdoPageBackground().ignoresSafeArea()
            VStack(spacing: 16) {
                MemdoBrandMark(size: 72)
                Text("Memdo")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .tracking(-0.3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MemdoSignInView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentNonce: String?

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
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            MemdoBrandMark(size: 72)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Memdo")

            Spacer(minLength: 64)

            VStack(spacing: 10) {
                appleSignInButton
                providerButton("Google로 계속", image: "GoogleSignIn", provider: .google)
                providerButton("GitHub로 계속", image: "GitHubSignIn", provider: .github)
            }

            signInFeedback
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var signInFeedback: some View {
        if session.isBusy {
            ProgressView("로그인 화면을 여는 중")
                .font(.caption)
                .padding(.top, 12)
        }

        if let errorMessage = session.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 12)
                .accessibilityLabel("로그인 오류: \(errorMessage)")
        }
    }

    private func providerButton(_ title: String, image: String, provider: Provider) -> some View {
        Button {
            Task { await session.signIn(with: provider) }
        } label: {
            HStack(spacing: 8) {
                providerLogo(image, provider: provider)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(providerBackground(provider), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if provider == .google {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(providerOutline, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(providerForeground(provider))
    }

    // GitHub ships a single-colour mark, so tint it to match the button surface;
    // Google's multi-colour logo must render as-is.
    @ViewBuilder
    private func providerLogo(_ image: String, provider: Provider) -> some View {
        if provider == .github {
            Image(image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Self.randomNonce()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            guard case let .success(authorization) = result,
                  let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce
            else { return }
            Task { await session.signInWithApple(idToken: idToken, nonce: nonce) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func providerBackground(_ provider: Provider) -> Color {
        switch provider {
        case .github:
            return colorScheme == .dark ? .white : .black
        default:
            return colorScheme == .dark ? Color(red: 19 / 255, green: 19 / 255, blue: 20 / 255) : .white
        }
    }

    private func providerForeground(_ provider: Provider) -> Color {
        switch provider {
        case .github:
            return colorScheme == .dark ? .black : .white
        default:
            return colorScheme == .dark ? .white : Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)
        }
    }

    private var providerOutline: Color {
        colorScheme == .dark
            ? Color(white: 1).opacity(0.18)
            : Color(red: 116 / 255, green: 119 / 255, blue: 117 / 255).opacity(0.4)
    }
}
