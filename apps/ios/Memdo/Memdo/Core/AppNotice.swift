import SwiftUI

/// A single transient user-facing message, error or success. Single-slot --
/// posting a new notice replaces whatever is currently shown, matching the
/// "dismissible, non-blocking" semantics every store-owned error field this
/// type replaces already had.
struct AppNotice: Identifiable, Equatable {
    enum Kind {
        case error
        case success
    }

    let id = UUID()
    let kind: Kind
    let message: String
}

/// App-wide error/success notice center. Replaces the ~10 independently
/// duplicated `String?` error fields (and their bespoke inline `Label` view
/// code) that used to be scattered across ScheduleStore, WorkoutStore,
/// PreferencesStore, MemdoSession, and several Settings sheets. Stores take
/// this as an init dependency (not an environment read) so a fire-and-forget
/// `Task { try? await scheduleStore.X() }` call site -- with no View in the
/// loop to read an environment value -- can still surface its own failure,
/// exactly the way `ScheduleStore.fail()` did before this type existed.
@MainActor
@Observable
final class AppNoticeCenter {
    private(set) var current: AppNotice?

    func error(_ message: String) {
        current = AppNotice(kind: .error, message: message)
    }

    func success(_ message: String) {
        current = AppNotice(kind: .success, message: message)
    }

    func dismiss() {
        current = nil
    }

    /// Only clears if `id` is still the notice on screen, so a stale
    /// auto-dismiss timer from an older notice can't clobber a newer one
    /// that has already replaced it.
    func dismiss(if id: AppNotice.ID) {
        if current?.id == id { current = nil }
    }
}

/// Floating bottom banner, generalizing AppShellView's former
/// `writeErrorToast`. Kind-aware icon/tint; reuses the same
/// VoiceOver/Switch-Control-aware auto-dismiss behavior verbatim (fd12).
/// Mount at any view whose presented `.sheet`s also need their own notices
/// visible -- a sheet covers its presenter's `.overlay`, so the app-shell
/// root alone does not cover a notice fired while a sheet is open.
private struct AppNoticeToastModifier: ViewModifier {
    @Environment(AppNoticeCenter.self) private var noticeCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) { toast }
    }

    @ViewBuilder
    private var toast: some View {
        if let notice = noticeCenter.current {
            Button {
                noticeCenter.dismiss()
            } label: {
                Label(notice.message, systemImage: icon(for: notice.kind))
                    .font(MemdoTypography.metric)
                    .foregroundStyle(notice.kind == .success ? MemdoTheme.activityAccent : MemdoTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, MemdoMetrics.pagePadding)
            .padding(.bottom, 12)
            .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel("\(notice.message). 닫으려면 두 번 탭하세요.")
            .task(id: notice.id) {
                AccessibilityNotification.Announcement(notice.message).post()
                // Suspended while VoiceOver/Switch Control is running so an
                // assistive-technology user has time to actually act on it
                // instead of it vanishing on the same fixed timer a sighted
                // user gets.
                guard !voiceOverEnabled, !switchControlEnabled else { return }
                try? await Task.sleep(for: MemdoMetrics.bannerDismissDuration)
                noticeCenter.dismiss(if: notice.id)
            }
        }
    }

    private func icon(for kind: AppNotice.Kind) -> String {
        switch kind {
        case .error: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        }
    }
}

/// Inline, in-page notice -- no overlay, no auto-dismiss timer. Generalizes
/// the ~9 duplicated `Label(errorMessage, systemImage: "exclamationmark...")`
/// blocks previously hand-rolled per screen (sign-in, Settings rows, sheet
/// sections).
struct AppNoticeInlineLabel: View {
    @Environment(AppNoticeCenter.self) private var noticeCenter

    var body: some View {
        if let notice = noticeCenter.current {
            Label(notice.message, systemImage: icon(for: notice.kind))
                .font(MemdoTypography.caption)
                .foregroundStyle(notice.kind == .success ? MemdoTheme.activityAccent : MemdoTheme.destructive)
        }
    }

    private func icon(for kind: AppNotice.Kind) -> String {
        switch kind {
        case .error: "exclamationmark.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }
}

extension View {
    /// Mounts the shared floating notice toast on this view.
    func appNoticeToast() -> some View {
        modifier(AppNoticeToastModifier())
    }
}
