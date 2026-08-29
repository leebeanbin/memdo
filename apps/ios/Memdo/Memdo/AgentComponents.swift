import SwiftUI

struct AgentSheetHeader: View {
    let context: AgentContext
    var hasStarted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(context.displayTitle) 문맥 사용 중", systemImage: "sparkles")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.brand)
            if !hasStarted {
                Text("무엇을 정리할까요?")
                    .font(MemdoTypography.detailTitle)
                Text("오늘 일정을 바탕으로 대화할 수 있어요. 질문하거나 요청해보세요.")
                    .font(MemdoTypography.subtitle)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
    }
}

struct AgentUserBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(MemdoTypography.subtitle)
            .foregroundStyle(MemdoTheme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MemdoTheme.accent, in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct AgentQuickActions: View {
    let context: AgentContext
    let hasSchedulesToday: Bool
    let onSelect: (String) -> Void

    private var prompts: [(String, String)] {
        AgentPrompts.quickActions(for: context, hasSchedulesToday: hasSchedulesToday)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("빠른 요청")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.secondaryInk)

            VStack(spacing: 0) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { index, item in
                    Button { onSelect(item.1) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .font(MemdoTypography.captionEmphasis)
                                .foregroundStyle(MemdoTheme.brand)
                                .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.0)
                                    .font(MemdoTypography.action)
                                Text(item.1)
                                    .font(MemdoTypography.caption)
                                    .foregroundStyle(MemdoTheme.secondaryInk)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(MemdoTheme.ink)
                        .padding(.horizontal, MemdoMetrics.rowInset)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < prompts.count - 1 {
                        Divider().padding(.leading, MemdoMetrics.rowContentLeading)
                    }
                }
            }
            .memdoRowGroup()
        }
    }
}

struct AgentResponse: View {
    let message: AgentMessage
    var onRetry: (() -> Void)? = nil

    private var accentColor: Color {
        message.isError ? .red : MemdoTheme.brand
    }

    private var isToolPhase: Bool {
        message.isStreaming && message.text.isEmpty && message.toolHint != nil
    }

    private var headerLabel: String {
        if message.isError                              { return "오류" }
        if isToolPhase                                  { return "실행 중" }
        if message.isStreaming && message.text.isEmpty  { return "생각 중…" }
        // Distinct from every other intent -- there's nothing to approve
        // here, just a question the user answers in their next message, so
        // this is deliberately NOT rendered like a proposal card header.
        if message.intent == .clarificationRequired      { return "확인이 필요해요" }
        return "Agent"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 6) {
                if isToolPhase {
                    Image(systemName: "gearshape.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                        .symbolEffect(.pulse)
                } else if message.isStreaming && message.text.isEmpty {
                    TypingDotsView()
                } else if message.isError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.red)
                } else if message.intent == .clarificationRequired {
                    Image(systemName: "questionmark.circle")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                } else {
                    Image(systemName: "sparkle")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                }
                Text(headerLabel)
                    .font(MemdoTypography.captionEmphasis)
                    .foregroundStyle(accentColor)
            }

            // Tool hint
            if let hint = message.toolHint, message.text.isEmpty {
                Text(hint)
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }

            // Main content — markdown-rendered
            if !message.text.isEmpty {
                AgentMarkdownText(text: message.text)
                    .font(MemdoTypography.subtitle)
                    .foregroundStyle(message.isError ? .red : MemdoTheme.ink)
                    .textSelection(.enabled)
            }

            // Retry
            if message.isError, let onRetry {
                Button(action: onRetry) {
                    Label("다시 시도", systemImage: "arrow.clockwise")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.brand)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, MemdoMetrics.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accentColor)
                .frame(width: 3)
        }
        .contextMenu {
            if !message.text.isEmpty {
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("복사하기", systemImage: "doc.on.doc")
                }
            }
            #if DEBUG
            // Founder/debug-only (D2) -- copies AgentDebugTrace.debugText to
            // the clipboard rather than a new sheet/view, matching "even a
            // raw dump is fine for this slice." #if DEBUG so a Release
            // build never compiles this in, regardless of whether the
            // backend ever sends a trace. Cloud turns only for now (see
            // AgentDebugTrace's doc comment).
            if let trace = message.debugTrace {
                Button {
                    UIPasteboard.general.string = trace.debugText
                } label: {
                    Label("디버그 추적 복사", systemImage: "ladybug")
                }
            }
            #endif
        }
    }
}

/// Line-based Markdown renderer for Agent responses.
/// `AttributedString(markdown:)` with `.inlineOnlyPreservingWhitespace`
/// (used directly on the whole message before this) parses inline emphasis
/// ("**bold**") correctly but has no concept of block-level list markers --
/// a line starting with "* " or "- " comes through as a literal asterisk
/// followed by the (correctly bold-rendered) rest of the line, which is
/// exactly the raw-looking output reported from a real model response. This
/// classifies each line first, renders list lines as an actual bullet row,
/// and still inline-parses each line's own text the same way as before.
struct AgentMarkdownText: View {
    let text: String

    struct Line: Identifiable, Equatable {
        let id: Int
        let isListItem: Bool
        let content: String
    }

    /// Exposed for testing the classification independent of the view body.
    static func lines(for text: String) -> [Line] {
        text.components(separatedBy: "\n").enumerated().map { index, raw in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                return Line(id: index, isListItem: true, content: String(trimmed.dropFirst(2)))
            }
            return Line(id: index, isListItem: false, content: raw)
        }
    }

    /// Exposed for testing inline-markdown parsing independent of the view body.
    static func inlineAttributed(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    private var lines: [Line] { Self.lines(for: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines) { line in
                if line.content.isEmpty {
                    Color.clear.frame(height: 6)
                } else if line.isListItem {
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundStyle(MemdoTheme.secondaryInk)
                        Text(Self.inlineAttributed(line.content))
                    }
                } else {
                    Text(Self.inlineAttributed(line.content))
                }
            }
        }
    }
}

private struct TypingDotsView: View {
    @State private var active = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(MemdoTheme.brand)
                    .frame(width: 6, height: 6)
                    .scaleEffect(active ? 1.0 : 0.3)
                    .opacity(active ? 1.0 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18),
                        value: active
                    )
            }
        }
        .onAppear { active = true }
    }
}

// MARK: - Proposed Schedule Card

struct ProposedScheduleCard: View {
    let draft: ProposedScheduleDraft
    var conflictTitle: String? = nil
    var conflictCheckFailed: Bool = false
    /// True while the confirm tap's Store mutation is actually in flight --
    /// disables the button so a rapid double-tap can't fire two requests.
    var isApplying: Bool = false
    let onConfirm: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "Agent" prefix makes the source explicit, matching this app's
            // documented proposal-card fields (제목·시간·반복·알림·출처) --
            // not just implied by "this card only ever appears inside the
            // Agent sheet."
            Label("Agent 일정 제안", systemImage: "calendar.badge.plus")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.brand)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.ink)

                HStack(spacing: 10) {
                    Label(draft.displayDate, systemImage: "calendar")
                    Label(draft.displayTime,
                          systemImage: draft.isTask ? "checkmark.circle" : "clock")
                }
                .font(MemdoTypography.caption)
                .foregroundStyle(MemdoTheme.secondaryInk)
                .lineLimit(1)

                if let note = draft.note, !note.isEmpty {
                    Text(note)
                        .font(MemdoTypography.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .lineLimit(2)
                }

                // Reflection result: ProposeScheduleTool already checked this
                // against the real schedule -- surfaced here so approval is an
                // informed choice, not just a rubber stamp.
                if let conflictTitle {
                    Label("같은 시간에 '\(conflictTitle)' 일정이 있어요", systemImage: "exclamationmark.triangle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if conflictCheckFailed {
                    Label("기존 일정을 확인하지 못했어요 — 저장 전 직접 확인해주세요", systemImage: "questionmark.circle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    HStack(spacing: 6) {
                        if isApplying {
                            ProgressView().tint(MemdoTheme.onAccent)
                        } else {
                            Label("저장하기", systemImage: "checkmark")
                        }
                    }
                    .font(MemdoTypography.captionEmphasis)
                    .foregroundStyle(MemdoTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(MemdoTheme.accent,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isApplying)

                Button(action: onDecline) {
                    Text("취소")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MemdoTheme.outline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isApplying)
            }
        }
        .padding(14)
        .background(MemdoTheme.brandSoft,
                    in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                .stroke(MemdoTheme.brand.opacity(0.2), lineWidth: 0.5)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }
}

/// Confirmation card for propose_schedule_update (complete/reschedule/delete
/// an EXISTING item) -- shared by both the cloud path and UpdateScheduleTool
/// (on-device), since both funnel into the same AgentScheduleUpdateProposal.
struct ProposedScheduleUpdateCard: View {
    let proposal: AgentScheduleUpdateProposal
    /// True while the confirm tap's Store mutation is actually in flight --
    /// disables the button so a rapid double-tap can't fire two requests.
    var isApplying: Bool = false
    let onConfirm: () -> Void
    let onDecline: () -> Void

    private var icon: String {
        switch proposal.action {
        case "complete":   return "checkmark.circle"
        case "reschedule": return "calendar.badge.clock"
        case "delete":     return "trash"
        default:           return "pencil"
        }
    }

    private var confirmLabel: String {
        proposal.action == "delete" ? "삭제하기" : "적용하기"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agent \(proposal.displayActionLabel) 제안", systemImage: icon)
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.brand)

            VStack(alignment: .leading, spacing: 6) {
                Text(proposal.title ?? "일정")
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.ink)

                if proposal.action == "reschedule", let displayDate = proposal.displayDate {
                    HStack(spacing: 10) {
                        Label(displayDate, systemImage: "calendar")
                        if let start = proposal.startTimeString {
                            Label(start + (proposal.endTimeString.map { " – \($0)" } ?? ""), systemImage: "clock")
                        }
                    }
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                    .lineLimit(1)
                }

                // Reflection result, same convention as ProposedScheduleCard
                // above -- surfaced before approval, not only after applying.
                if let conflictTitle = proposal.conflict?.title {
                    Label("같은 시간에 '\(conflictTitle)' 일정이 있어요", systemImage: "exclamationmark.triangle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if proposal.conflictCheckFailed {
                    Label("기존 일정을 확인하지 못했어요 — 적용 전 직접 확인해주세요", systemImage: "questionmark.circle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    HStack(spacing: 6) {
                        if isApplying {
                            ProgressView().tint(MemdoTheme.onAccent)
                        } else {
                            Label(confirmLabel, systemImage: "checkmark")
                        }
                    }
                    .font(MemdoTypography.captionEmphasis)
                    .foregroundStyle(MemdoTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(MemdoTheme.accent,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isApplying)

                Button(action: onDecline) {
                    Text("취소")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MemdoTheme.outline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isApplying)
            }
        }
        .padding(14)
        .background(MemdoTheme.brandSoft,
                    in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                .stroke(MemdoTheme.brand.opacity(0.2), lineWidth: 0.5)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }
}

/// Confirmation card for propose_routine_update -- shows only the fields the
/// model actually proposed changing (every field on the DTO is optional).
struct ProposedRoutineUpdateCard: View {
    let draft: CloudProposedRoutineUpdateDTO
    let onConfirm: () -> Void
    let onDecline: () -> Void

    private var rows: [String] {
        var lines: [String] = []
        if let v = draft.dailyReviewEnabled {
            lines.append("하루 정리: " + (v ? "켜짐" : "꺼짐") + (draft.dailyReviewTime.map { " · \($0)" } ?? ""))
        } else if let time = draft.dailyReviewTime {
            lines.append("하루 정리 시간: \(time)")
        }
        if let v = draft.newsBriefingEnabled {
            lines.append("뉴스 브리핑: " + (v ? "켜짐" : "꺼짐") + (draft.newsBriefingTime.map { " · \($0)" } ?? ""))
        } else if let time = draft.newsBriefingTime {
            lines.append("뉴스 브리핑 시간: \(time)")
        }
        if let time = draft.planningPromptTime {
            lines.append("하루 시작 시간: \(time)")
        }
        if let v = draft.notificationsEnabled {
            lines.append("전체 알림: " + (v ? "켜짐" : "꺼짐"))
        }
        return lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agent 루틴 설정 변경 제안", systemImage: "gearshape.badge.checkmark")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.brand)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.self) { row in
                    Text(row)
                        .font(MemdoTypography.action)
                        .foregroundStyle(MemdoTheme.ink)
                }
            }

            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    Label("적용하기", systemImage: "checkmark")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.accent,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDecline) {
                    Text("취소")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MemdoTheme.outline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(MemdoTheme.brandSoft,
                    in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                .stroke(MemdoTheme.brand.opacity(0.2), lineWidth: 0.5)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }
}

/// Confirmation card for propose_review_actions -- a proposed reflection
/// *text* for one day. Resolves the model's raw date token once (via the
/// shared AgentDateExpression) and, if it resolves, checks for an existing
/// reflection on that date before letting the user approve, so an approval
/// can never silently overwrite something already written without the user
/// having seen it.
struct ProposedReviewActionCard: View {
    let scheduleStore: ScheduleStore
    let draft: CloudProposedReviewActionDTO
    let onConfirm: () -> Void
    let onDecline: () -> Void

    @State private var isCheckingExistingReview = true
    @State private var existingReview: ReviewDTO?

    private var resolvedDate: Date? {
        AgentDateExpression(token: draft.date)?.resolvedDate()
    }

    private var displayDate: String? {
        resolvedDate.map { DateFormatting.korean("M월 d일").string(from: $0) }
    }

    private var apiDateString: String? {
        resolvedDate.map { DateFormatting.posix("yyyy-MM-dd").string(from: $0) }
    }

    /// A row existing with a nil/blank reflection is treated as "nothing to
    /// overwrite" -- same as no row at all.
    private var existingReflectionText: String? {
        guard let text = existingReview?.reflection else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agent 회고 제안", systemImage: "text.book.closed")
                .font(MemdoTypography.captionEmphasis)
                .foregroundStyle(MemdoTheme.brand)

            VStack(alignment: .leading, spacing: 6) {
                if let displayDate {
                    Label(displayDate, systemImage: "calendar")
                        .font(MemdoTypography.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                } else {
                    Label("날짜를 확인할 수 없어요", systemImage: "exclamationmark.triangle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                }

                Text(draft.reflection)
                    .font(MemdoTypography.action)
                    .foregroundStyle(MemdoTheme.ink)

                if let existingReflectionText {
                    Label("이 날짜에 이미 회고가 있어요: \"\(existingReflectionText)\" 덮어쓸까요?",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
            }

            HStack(spacing: 8) {
                if resolvedDate != nil {
                    Button(action: onConfirm) {
                        Label("저장하기", systemImage: "checkmark")
                            .font(MemdoTypography.captionEmphasis)
                            .foregroundStyle(MemdoTheme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(MemdoTheme.accent,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    // Disabled for the entire duration of the existence
                    // check, not just while a conflict is confirmed -- so
                    // the user can't approve before the warning (if any)
                    // has had a chance to render.
                    .disabled(isCheckingExistingReview)
                }

                Button(action: onDecline) {
                    Text("취소")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MemdoTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MemdoTheme.outline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(MemdoTheme.brandSoft,
                    in: RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MemdoMetrics.contentRadius, style: .continuous)
                .stroke(MemdoTheme.brand.opacity(0.2), lineWidth: 0.5)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
        .task(id: draft.date) {
            // Reset together at the start of every new date's check -- a
            // warning from a previous proposal's date must never remain
            // visible while this one is still in flight.
            isCheckingExistingReview = true
            existingReview = nil
            guard let apiDateString else {
                isCheckingExistingReview = false
                return
            }
            do {
                existingReview = try await scheduleStore.review(on: apiDateString)
            } catch {
                // Fails open on the *result* only (no warning shown, still
                // approvable) -- never on whether the check ran; the button
                // stays disabled until this reaches here regardless of
                // outcome.
                existingReview = nil
            }
            isCheckingExistingReview = false
        }
    }
}

// MARK: - Composer

struct AgentComposer: View {
    @Binding var text: String
    var isLoading: Bool = false
    let onSend: () -> Void

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("어떤 일을 정리할까요?", text: $text)
                .onSubmit(onSend)
                .disabled(isLoading)
                .padding(.leading, MemdoMetrics.rowInset)
                .frame(minHeight: MemdoMetrics.touchTarget)

            Button(action: onSend) {
                if isLoading {
                    ProgressView()
                        .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(isEmpty ? MemdoTheme.secondaryInk : MemdoTheme.brand)
                        .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
                        .contentShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(isEmpty || isLoading)
            .accessibilityLabel("요청 보내기")
        }
        .padding(4)
        .memdoFloatingSurface(cornerRadius: MemdoMetrics.groupRadius, interactive: false)
    }
}

// MARK: - Output gallery (Preview only)

/// Every shape an Agent message/card can render in, side by side, so a
/// change to any of them can be checked visually without hand-triggering
/// each state in the simulator (loading/error/tool-call require timing or a
/// live key; the proposal cards require a real tool call). Not shown at
/// runtime -- Xcode canvas / #Preview only.
private struct AgentOutputGallery: View {
    private static let markdownBugRepro = """
        오늘의 일정을 알려줄게.

        * **제안 일정**: 오늘 일정을 제안해줄게.
        * **공백 시간 찾기**: 오늘의 공백 시간을 찾아줄게.
        * **일정 수정하기**: 오늘의 일정을 수정해줄게.

        만약 다른 기능이 필요하시면 알려주세요!
        """

    private var conflictFreeScheduleProposal: AgentScheduleProposal {
        let p = AgentScheduleProposal()
        p.propose(ProposedScheduleDraft(
            title: "집중 업무", dateString: "today",
            startTimeString: "14:00", endTimeString: "15:00",
            isTask: false, note: nil
        ))
        return p
    }

    private var conflictingScheduleProposal: AgentScheduleProposal {
        let p = AgentScheduleProposal()
        p.propose(
            ProposedScheduleDraft(
                title: "점심 약속", dateString: "today",
                startTimeString: "12:00", endTimeString: "13:00",
                isTask: false, note: "동료와 함께"
            ),
            conflict: AgentConflictSnapshot(id: "preview-conflict-1", title: "팀 회의")
        )
        return p
    }

    private var checkFailedScheduleProposal: AgentScheduleProposal {
        let p = AgentScheduleProposal()
        p.propose(
            ProposedScheduleDraft(
                title: "독서", dateString: "tomorrow",
                startTimeString: nil, endTimeString: nil,
                isTask: true, note: nil
            ),
            conflictCheckFailed: true
        )
        return p
    }

    private var completeUpdateProposal: AgentScheduleUpdateProposal {
        let p = AgentScheduleUpdateProposal()
        p.propose(
            id: "1", action: "complete", title: "보고서 작성",
            dateString: nil, startTimeString: nil, endTimeString: nil,
            conflict: nil, conflictCheckFailed: false
        )
        return p
    }

    private var rescheduleConflictUpdateProposal: AgentScheduleUpdateProposal {
        let p = AgentScheduleUpdateProposal()
        p.propose(
            id: "2", action: "reschedule", title: "팀 회의",
            dateString: "tomorrow", startTimeString: "10:00", endTimeString: "11:00",
            conflict: AgentConflictSnapshot(id: "preview-conflict-2", title: "1:1 미팅"), conflictCheckFailed: false
        )
        return p
    }

    private var deleteUpdateProposal: AgentScheduleUpdateProposal {
        let p = AgentScheduleUpdateProposal()
        p.propose(
            id: "3", action: "delete", title: "취소된 약속",
            dateString: nil, startTimeString: nil, endTimeString: nil,
            conflict: nil, conflictCheckFailed: false
        )
        return p
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(MemdoTypography.captionEmphasis)
            .foregroundStyle(MemdoTheme.secondaryInk)
            .padding(.top, 4)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                label("사용자 버블")
                AgentUserBubble(text: "오늘 일정 알려줘")

                label("Agent 응답 — 일반 텍스트")
                AgentResponse(message: AgentMessage(role: .assistant, text: "오늘은 회의가 2개 있어요."))

                label("Agent 응답 — 마크다운 목록 (버그 재현 케이스)")
                AgentResponse(message: AgentMessage(role: .assistant, text: Self.markdownBugRepro))

                label("Agent 응답 — 생각 중")
                AgentResponse(message: AgentMessage(role: .assistant, text: "", isStreaming: true))

                label("Agent 응답 — 도구 실행 중")
                AgentResponse(message: AgentMessage(
                    role: .assistant, text: "", isStreaming: true, toolHint: "일정을 제안하는 중..."
                ))

                label("Agent 응답 — 오류 (재시도 가능)")
                AgentResponse(
                    message: AgentMessage(role: .assistant, text: "오류가 발생했어요. 다시 시도해주세요.", isError: true),
                    onRetry: {}
                )

                label("일정 제안 카드 — 충돌 없음")
                ProposedScheduleCard(
                    draft: conflictFreeScheduleProposal.draft!,
                    conflictTitle: nil, conflictCheckFailed: false,
                    onConfirm: {}, onDecline: {}
                )

                label("일정 제안 카드 — 충돌 있음")
                ProposedScheduleCard(
                    draft: conflictingScheduleProposal.draft!,
                    conflictTitle: conflictingScheduleProposal.conflict?.title, conflictCheckFailed: false,
                    onConfirm: {}, onDecline: {}
                )

                label("일정 제안 카드 — 충돌 확인 실패")
                ProposedScheduleCard(
                    draft: checkFailedScheduleProposal.draft!,
                    conflictTitle: nil, conflictCheckFailed: true,
                    onConfirm: {}, onDecline: {}
                )

                label("일정 변경 카드 — 완료 처리")
                ProposedScheduleUpdateCard(proposal: completeUpdateProposal, onConfirm: {}, onDecline: {})

                label("일정 변경 카드 — 이동 (충돌 있음)")
                ProposedScheduleUpdateCard(proposal: rescheduleConflictUpdateProposal, onConfirm: {}, onDecline: {})

                label("일정 변경 카드 — 삭제")
                ProposedScheduleUpdateCard(proposal: deleteUpdateProposal, onConfirm: {}, onDecline: {})
            }
            .padding(MemdoMetrics.pagePadding)
        }
        .background(MemdoTheme.background)
    }
}

#Preview("Agent 출력 갤러리") {
    AgentOutputGallery()
}
