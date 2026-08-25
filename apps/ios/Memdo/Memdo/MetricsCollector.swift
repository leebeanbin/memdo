import Foundation
import MetricKit
import os

/// Minimum-viable MetricKit crash/hang diagnostics (Epic M, v1.0) -- a
/// safety net for diagnosing what testers hit during beta, not a full
/// observability platform. See docs/23-observability-and-alerting.md for
/// what this deliberately does and doesn't cover, and the Sentry decision
/// gate recorded in docs/09-roadmap-and-backlog.md's v1.0 entry.
///
/// iOS 27+ SDK note: Apple introduced a newer `MetricManager` async-sequence
/// API. As of this writing, the production (non-beta) Xcode installed here
/// is 26.6 with only an iOS 26.5 SDK -- no iOS 27 SDK is available, so code
/// referencing the new API wouldn't even compile, let alone ship. This
/// subscriber uses the legacy `MXMetricManagerSubscriber` delegate path
/// exclusively for now. Once a production Xcode ships an iOS 27 SDK, add
/// the new API path gated by `if #available(iOS 27, *)` ALONGSIDE this one
/// (not replacing it -- iOS 17-26 devices still need this path).
/// Deployment target stays iOS 17.0 either way.
///
/// Diagnostic payload fields verified directly against this machine's
/// installed SDK headers (MXCrashDiagnostic.h/MXHangDiagnostic.h/
/// MXDiagnostic.h) before writing this -- confirmed no field on
/// MXDiagnostic/MXCrashDiagnostic/MXHangDiagnostic carries app content
/// (schedule titles, Agent messages, etc.): applicationVersion, a
/// call-stack tree, termination reason/exception/signal codes, hang
/// duration. All system/stack-trace metadata, by Apple's own design.
///
/// Default posture: log locally only (os.Logger, inspectable via
/// Console.app/sysdiagnose on a connected device) -- nothing is
/// transmitted anywhere. TestFlight/App Store builds also get
/// automatically-collected, separately-symbolicated crash reports in
/// Xcode Organizer regardless of this subscriber (that collection doesn't
/// depend on app code at all); this subscriber is a complementary,
/// in-process channel, not a replacement for checking Organizer.
@MainActor
final class MetricsCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsCollector()

    // A plain `nonisolated static let` rather than an instance property --
    // Logger is a Sendable value type, and didReceive(_:) below is
    // nonisolated (called off the main actor), so it needs a logger it can
    // reach without going through the @MainActor-isolated `shared` instance
    // (every member of this class is MainActor-isolated by default;
    // `nonisolated` opts this one back out).
    nonisolated static let sharedLogger = Logger(subsystem: "com.memdo.ios", category: "metrickit")

    private override init() {
        super.init()
    }

    /// Call once, early in MemdoApp's lifecycle (before any diagnostics
    /// could plausibly be delivered) -- mirrors how other long-lived
    /// services are constructed with the App struct.
    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // MXMetricManagerSubscriber callbacks arrive on a background queue
        // (per MXMetricManager.h's own doc comment). os.Logger is
        // thread-safe to call from any queue, and MXDiagnosticPayload
        // isn't Sendable, so this stays nonisolated and processes the
        // array in place rather than hopping to the main actor with it.
        for payload in payloads {
            MetricsCollector.logDiagnostics(payload, logger: MetricsCollector.sharedLogger)
        }
    }

    /// Factored out from didReceive so the actual field-selection logic
    /// (what gets read out of a payload) is reviewable independent of a
    /// real MXDiagnosticPayload delivery -- delivery itself can't be
    /// triggered from a simulator or a unit test (MetricKit is
    /// system-scheduled, real-device only), but this makes clear exactly
    /// what would be logged if it were.
    nonisolated static func logDiagnostics(_ payload: MXDiagnosticPayload, logger: Logger) {
        for diagnostic in payload.crashDiagnostics ?? [] {
            logger.error(
                """
                MetricKit crash diagnostic: appVersion=\(diagnostic.applicationVersion, privacy: .public) \
                signal=\(diagnostic.signal?.stringValue ?? "nil", privacy: .public) \
                exceptionType=\(diagnostic.exceptionType?.stringValue ?? "nil", privacy: .public) \
                terminationReason=\(diagnostic.terminationReason ?? "nil", privacy: .public)
                """
            )
        }
        for diagnostic in payload.hangDiagnostics ?? [] {
            logger.error(
                """
                MetricKit hang diagnostic: appVersion=\(diagnostic.applicationVersion, privacy: .public) \
                durationSeconds=\(diagnostic.hangDuration.converted(to: .seconds).value, privacy: .public)
                """
            )
        }
    }
}
