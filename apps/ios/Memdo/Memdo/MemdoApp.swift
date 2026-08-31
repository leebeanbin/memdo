import AuthenticationServices
import CryptoKit
import Observation
import Supabase
import SwiftUI
import UserNotifications

@main
struct MemdoApp: App {
    @State private var session = MemdoSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MemdoRootView(session: session)
                .environment(session)
                .font(MemdoTypography.body)
                .dynamicTypeSize(.xSmall ... .accessibility3)
                .onOpenURL { session.handle($0) }
                .task { await session.observe() }
                .task {
                    UNUserNotificationCenter.current().delegate = MemdoNotificationDelegate.shared
                    NotificationScheduler.registerCategories()
                    MetricsCollector.shared.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Drain workouts queued from the Share Extension one at a time
                    // so a crash between dequeue and save loses only one item, not all.
                    while let pw = PendingWorkoutStore.dequeueOne() {
                        let duration = max(1, Int(pw.endedAt.timeIntervalSince(pw.startedAt)))
                        let log = WorkoutLog(
                            activityType: WorkoutActivityType(rawValue: pw.activityType) ?? .other,
                            startedAt: pw.startedAt,
                            endedAt: pw.endedAt,
                            durationSeconds: duration,
                            notes: pw.notes
                        )
                        session.workoutStore.save(log)
                    }
                    // Rolling-window reconciliation (docs/07 §10) at app
                    // activation -- the same trigger this session's Epic L
                    // plan named as the reuse target, rather than inventing
                    // a new lifecycle hook.
                    Task { await session.scheduleStore?.reconcileNotifications() }
                }
        }
    }
}

@MainActor
@Observable
final class MemdoSession {
    enum Phase: Equatable {
        case loading
        case signedOut
        case guest
        case signedIn
        case failed(String)
    }

    private(set) var phase = Phase.loading
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var accountLabel = ""
    private(set) var providerLabel = ""
    let scheduleStore: ScheduleStore?
    let preferencesStore: PreferencesStore?
    let workoutStore: WorkoutStore

    private let client: SupabaseClient?
    private var activeUserID: UUID?

    init() {
        var ws = WorkoutStore()
        do {
            let configuration = try MemdoConfiguration.current()
            let client = SupabaseClient(
                supabaseURL: configuration.projectURL,
                supabaseKey: configuration.publishableKey,
                options: SupabaseClientOptions(
                    // Without emitLocalSessionAsInitialSession, a launch-time refresh of an
                    // expired-but-real session that fails for a transport reason (offline,
                    // timeout, 5xx) emits .initialSession(nil) indistinguishably from true
                    // first launch, and observe() below would silently mint a brand new
                    // guest account, orphaning the old one. With it, the locally stored
                    // session (if any) is always emitted first; refresh happens afterward
                    // in the background.
                    //
                    // storage: DeviceOnlyKeychainStorage keeps the SDK's default Keychain
                    // timing but excludes the item from encrypted backups / cross-device
                    // restore -- see SecureSessionStorage.swift.
                    auth: .init(
                        storage: DeviceOnlyKeychainStorage(),
                        emitLocalSessionAsInitialSession: true
                    ),
                    global: .init(logger: MemdoAuthLogger())
                )
            )
            self.client = client
            scheduleStore = ScheduleStore(
                repository: ScheduleRepository(configuration: configuration, auth: client)
            )
            preferencesStore = PreferencesStore(
                repository: PreferencesRepository(configuration: configuration, auth: client)
            )
            ws = WorkoutStore(
                repository: WorkoutRepository(configuration: configuration, auth: client)
            )
        } catch {
            client = nil
            scheduleStore = nil
            preferencesStore = nil
            phase = .failed(error.localizedDescription)
        }
        workoutStore = ws
    }

    func observe() async {
        guard let client else { return }
        for await (event, session) in client.auth.authStateChanges {
            if let session {
                guard !session.user.isAnonymous else {
                    // Anonymous users enter guest mode -- data is stored in Supabase
                    // under their anonymous user_id and stays there when they later
                    // link a social identity (be18: signIn(with:)/signInWithApple
                    // call client.auth.linkIdentity*, not signInWith*, while a guest
                    // session is active, so user.id is unchanged by the upgrade).
                    if activeUserID != session.user.id {
                        await scheduleStore?.reset()
                        preferencesStore?.reset()
                        workoutStore.reset()
                    }
                    activeUserID = session.user.id
                    accountLabel = "게스트"
                    providerLabel = ""
                    phase = .guest
                    continue
                }
                if activeUserID != session.user.id {
                    await scheduleStore?.reset()
                    preferencesStore?.reset()
                    workoutStore.reset()
                }
                activeUserID = session.user.id
                accountLabel = session.user.email ?? "연결된 계정"
                let rawProvider = session.user.identities?.first?.provider ?? ""
                providerLabel = MemdoSession.formatProvider(rawProvider)
                phase = .signedIn
                continue
            }

            activeUserID = nil
            accountLabel = ""
            providerLabel = ""
            await scheduleStore?.reset()
            preferencesStore?.reset()
            workoutStore.reset()

            switch event {
            case .initialSession:
                // No existing session on launch — silently create an anonymous guest
                // session so the user enters the app without a sign-in screen.
                Task {
                    await signInAnonymously()
                    // If the device is offline or Supabase is unreachable, fall back
                    // to the sign-in screen so the user can see the error and retry.
                    if phase == .loading { phase = .signedOut }
                }
            case .signedOut:
                // User explicitly signed out from Settings → show the sign-in screen.
                phase = .signedOut
            default:
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
            // be18: signInWithOAuth authenticates into whatever account this
            // identity already belongs to (or a new one) -- independent of
            // the current session. Calling it from a guest session doesn't
            // upgrade the anonymous account, it silently switches to a
            // different one and orphans everything the guest created.
            // linkIdentity attaches the new identity to the CURRENT session
            // instead, keeping the same user.id.
            if phase == .guest {
                try await client.auth.linkIdentity(provider: provider, redirectTo: redirectURL)
            } else {
                try await client.auth.signInWithOAuth(provider: provider, redirectTo: redirectURL)
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithApple(idToken: String, nonce: String, authorizationCode: String?) async {
        guard let client else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            // be18: same reasoning as signIn(with:) above -- link to the
            // current guest session instead of signing into a separate one.
            if phase == .guest {
                try await client.auth.linkIdentityWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
            } else {
                try await client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Best-effort, and deliberately after signInWithIdToken already
        // succeeded: this exchange (Epic L) is what makes real Apple token
        // revocation possible at account-deletion time, but it must never
        // turn into a sign-in failure -- the user is already signed in by
        // this point. The code is single-use/~5-minute-lived, so this must
        // run at every Apple sign-in, not just the first. A nil
        // authorizationCode (shouldn't happen, but defensively handled at
        // the call site) just skips this step.
        guard let authorizationCode else { return }
        do {
            try await scheduleStore?.exchangeAppleAuthCode(authorizationCode)
        } catch {
            // Swallowed deliberately -- see comment above. If this keeps
            // failing, account deletion still works (fail-open), just
            // without a stored token to revoke for this user.
        }
    }

    func signInAnonymously() async {
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

    static func formatProvider(_ raw: String) -> String {
        switch raw {
        case "apple":  "Apple로 로그인"
        case "google": "Google로 로그인"
        case "github": "GitHub로 로그인"
        default:       raw.isEmpty ? "" : "\(raw) 계정으로 로그인"
        }
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
        case .guest:
            if let scheduleStore = session.scheduleStore {
                AppShellView(scheduleStore: scheduleStore)
                    .environment(session.workoutStore)
            }
        case .signedIn:
            if let scheduleStore = session.scheduleStore {
                AppShellView(scheduleStore: scheduleStore)
                    .environment(session.workoutStore)
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
                    .font(MemdoTypography.brand)
                    .tracking(-0.3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct MemdoSignInView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentNonce: String?

    let session: MemdoSession
    /// When set, shows a compact header with sparkle icon instead of the brand logo.
    /// Used by GuestLoginGateSheet to reuse sign-in buttons without duplication.
    var gateTitle: String? = nil
    var gateSubtitle: String? = nil

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

    // Per-provider fill following each brand's official button guidelines.
    private func providerFill(_ provider: Provider) -> Color {
        switch provider {
        case .google:
            return colorScheme == .dark
                ? Color(red: 0.075, green: 0.075, blue: 0.078)  // #131314 (Google dark)
                : .white
        case .github:
            return Color(red: 0.141, green: 0.161, blue: 0.184) // #24292F (GitHub)
        default:
            return colorScheme == .dark ? .white : .black        // Apple
        }
    }

    private func providerText(_ provider: Provider) -> Color {
        switch provider {
        case .google:
            return colorScheme == .dark
                ? .white
                : Color(red: 0.459, green: 0.459, blue: 0.459)  // #757575 (Google light)
        case .github:
            return .white
        default:
            return colorScheme == .dark ? .black : .white        // Apple
        }
    }

    private var signInContent: some View {
        VStack(spacing: 0) {
            if let gateTitle {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(MemdoTheme.brandInk)
                    Text(gateTitle)
                        .font(MemdoTypography.detailTitle)
                    if let gateSubtitle {
                        Text(gateSubtitle)
                            .font(MemdoTypography.subtitle)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 44)
            } else {
                Spacer(minLength: 48)

                MemdoBrandMark(size: 72)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Memdo")

                Spacer(minLength: 64)
            }

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
                .font(MemdoTypography.caption)
                .padding(.top, 12)
        }

        if let errorMessage = session.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(MemdoTypography.caption)
                .foregroundStyle(.red)
                .padding(.top, 12)
                .accessibilityLabel("로그인 오류: \(errorMessage)")
        }
    }

    // Icon + text centered together — consistent layout across all three buttons.
    private func providerButton(_ title: String, image: String, provider: Provider) -> some View {
        Button {
            Task { await session.signIn(with: provider) }
        } label: {
            signInButtonBody(fill: providerFill(provider), label: providerText(provider)) {
                Image(image)
                    .renderingMode(provider == .google ? .original : .template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(MemdoTypography.action)
                    .lineLimit(1)
            }
            // Google's white-background variant requires a subtle border so the
            // button is distinguishable from the page background.
            .overlay {
                if provider == .google && colorScheme == .light {
                    RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                        .stroke(Color(white: 0, opacity: 0.12), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var appleSignInButton: some View {
        ZStack {
            // Real Sign in with Apple button — handles the auth flow.
            // Kept nearly invisible so SwiftUI's hit-testing routes taps to it.
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
                // authorizationCode is expected to always be present alongside
                // identityToken for this credential type, but its absence must
                // never block sign-in itself -- only the (also best-effort)
                // Apple token-revocation setup in Epic L depends on it.
                let authorizationCode = credential.authorizationCode
                    .flatMap { String(data: $0, encoding: .utf8) }
                Task {
                    await session.signInWithApple(
                        idToken: idToken,
                        nonce: nonce,
                        authorizationCode: authorizationCode
                    )
                }
            }
            .opacity(0.011)
            .frame(height: 52)

            // Custom visual layer: Korean label + same centered layout as other buttons.
            signInButtonBody(fill: providerFill(.apple), label: providerText(.apple)) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 20, height: 20)
                Text("Apple로 계속")
                    .font(MemdoTypography.action)
                    .lineLimit(1)
            }
            .allowsHitTesting(false)
        }
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
    }

    @ViewBuilder
    private func signInButtonBody<Content: View>(
        fill: Color,
        label: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) { content() }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(fill, in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
        .foregroundStyle(label)
        .contentShape(Rectangle())
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
