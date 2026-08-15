import FoundationModels
import SwiftUI

// Typed action model (inspired by OpenWorker's risk classes): extracting/reading
// is automatic; creating or modifying a schedule requires explicit approval;
// off-device side effects are always explicit. Phase 2 only auto-runs `.read` —
// the event is created only after the user approves it in the editor.
enum ProposalRisk {
    case read
    case write
    case external
}

/// A proposed event extracted from freeform text, shown for review before it
/// becomes a real schedule.
struct EventDraft {
    var title: String
    var startAt: Date?
    var endAt: Date?
    var notes: String
    /// Extracted meeting link (Zoom/Meet/Teams), ready to write to `meetingURLString`.
    var meetingURL: URL?
    /// A short "transcript" of what was inferred and how, for transparency.
    var provenance: [String]
}

protocol EventExtractor {
    func extract(from text: String) async -> EventDraft
}

// MARK: - Deterministic baseline (every device)

/// Uses NSDataDetector for the date and meeting-link detection, and the first
/// line as a title. Reliable, offline, and never wrong about dates the way an
/// LLM can be — so the risky field (when) never depends on the model.
struct HeuristicEventExtractor: EventExtractor {
    func extract(from text: String) async -> EventDraft {
        Self.baseDraft(from: text)
    }

    static func baseDraft(from text: String) -> EventDraft {
        var provenance: [String] = []
        var startAt: Date?
        var endAt: Date?

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector.firstMatch(in: text, range: range), let date = match.date {
                startAt = date
                endAt = date.addingTimeInterval(match.duration > 0 ? match.duration : 3_600)
                provenance.append("시간 인식")
            }
        }

        var meetingURL: URL? = nil
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let url = match.url, MeetingProvider.recognized(url) != nil {
                    meetingURL = url
                    provenance.append("회의 링크 감지")
                    break
                }
            }
        }

        return EventDraft(
            title: firstLineTitle(from: text),
            startAt: startAt,
            endAt: endAt,
            notes: text,
            meetingURL: meetingURL,
            provenance: provenance
        )
    }

    static func firstLineTitle(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(line.trimmingCharacters(in: .whitespaces).prefix(60))
    }

    static func hasMeetingLink(in text: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).contains { $0.url.flatMap(MeetingProvider.recognized) != nil }
    }
}

// MARK: - On-device Apple Intelligence (title only; date stays deterministic)

@available(iOS 26, *)
@Generable
private struct ExtractedEventFields {
    @Guide(description: "A concise event title in two to six words. No dates, times, or URLs.")
    var title: String
}

@available(iOS 26, *)
struct IntelligenceEventExtractor: EventExtractor {
    func extract(from text: String) async -> EventDraft {
        var draft = HeuristicEventExtractor.baseDraft(from: text)
        guard SystemLanguageModel.default.isAvailable else { return draft }
        do {
            let session = LanguageModelSession(
                instructions: """
                Extract a concise calendar event title from the user's text. \
                Reply with a title only — no dates, times, or URLs.
                """
            )
            let response = try await session.respond(to: text, generating: ExtractedEventFields.self)
            let aiTitle = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !aiTitle.isEmpty {
                draft.title = aiTitle
                draft.provenance.insert("제목 · AI", at: 0)
            }
        } catch {
            // Fall back to the heuristic title on any model error.
        }
        return draft
    }
}

enum EventCapture {
    static var isIntelligenceAvailable: Bool {
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    static func extractor() -> EventExtractor {
        if #available(iOS 26, *), SystemLanguageModel.default.isAvailable {
            return IntelligenceEventExtractor()
        }
        return HeuristicEventExtractor()
    }
}

// MARK: - Capture sheet

struct EventCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var draft: EventDraft? = nil
    @State private var isAnalyzing = false
    @FocusState private var isTextFocused: Bool

    let onApply: (EventDraft) -> Void

    init(initialText: String = "", onApply: @escaping (EventDraft) -> Void) {
        _text = State(initialValue: initialText)
        self.onApply = onApply
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "줌 링크, ‘목요일 3시’, 초대 메일 등을 붙여넣으세요",
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(4...10)
                    .focused($isTextFocused)
                } footer: {
                    Text(EventCapture.isIntelligenceAvailable
                        ? "제목은 기기 안에서 AI가, 시간은 자동 인식해요. 추가 전 항상 확인합니다."
                        : "시간과 링크를 자동 인식해요. 추가 전 항상 확인합니다.")
                }

                if let draft {
                    Section("제안") {
                        LabeledContent("제목", value: draft.title.isEmpty ? "없음" : draft.title)
                        if let start = draft.startAt {
                            LabeledContent("시간", value: start.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let provider = draft.meetingURL.flatMap(MeetingProvider.recognized) {
                            LabeledContent("회의", value: provider.label)
                        }
                        if !draft.provenance.isEmpty {
                            Label(draft.provenance.joined(separator: " · "), systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                    }
                }
            }
            .memdoSystemList()
            .navigationTitle("빠른 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAnalyzing {
                        ProgressView()
                            .accessibilityLabel("일정 분석 중")
                    } else if draft == nil {
                        Button("분석") { analyze() }
                            .disabled(trimmed.isEmpty)
                    } else {
                        Button("채우기") {
                            if let draft { onApply(draft) }
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .memdoSheetPresentation([.medium, .large])
        .task {
            if trimmed.isEmpty {
                isTextFocused = true
            } else {
                analyze()
            }
        }
    }

    private func analyze() {
        isAnalyzing = true
        Task {
            let result = await EventCapture.extractor().extract(from: trimmed)
            draft = result
            isAnalyzing = false
        }
    }
}
