import SwiftUI

struct AgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var composer: String
    @Binding var response: String

    let context: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
                    AgentSheetHeader(context: context)
                    if !response.isEmpty {
                        AgentResponse(text: response)
                    } else {
                        AgentQuickActions(context: context, onSelect: selectQuickAction)
                    }
                }
                .padding(MemdoMetrics.pagePadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MemdoTheme.background)
            .safeAreaInset(edge: .bottom) {
                AgentComposer(text: $composer, onSend: send)
                    .padding(.horizontal, MemdoMetrics.pagePadding)
                    .padding(.vertical, 6)
            }
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("새 대화", systemImage: "square.and.pencil", action: resetConversation)
                        .disabled(composer.isEmpty && response.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.medium, .large])
    }

    private func selectQuickAction(_ prompt: String) {
        composer = prompt
        send()
    }

    private func send() {
        let prompt = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        // Agent isn't implemented yet -- this is a preview of the composer/response
        // layout, not a real response, so the copy says so rather than sounding
        // like a genuine (if canned) confirmation of the request.
        response = "Agent는 아직 준비 중이에요. ‘\(prompt)’ 요청은 지금은 실제로 처리되지 않아요."
        composer = ""
    }

    private func resetConversation() {
        composer = ""
        response = ""
    }
}

private struct AgentSheetHeader: View {
    let context: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(context) 문맥 사용 중", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoTheme.brand)
            Text("무엇을 정리할까요?")
                .font(.title2.bold())
            Text("읽기와 제안은 바로, 변경은 확인 뒤 실행합니다.")
                .font(.subheadline)
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
    }
}

private struct AgentQuickActions: View {
    let context: String
    let onSelect: (String) -> Void

    private var prompts: [(String, String)] {
        switch context {
        case "캘린더": [
            ("빈 시간 찾기", "이번 주에 1시간 비는 시간 찾아줘"),
            ("일정 정리", "겹치거나 너무 붙은 일정 알려줘"),
            ("할 일 배치", "미완료 할 일을 빈 시간에 제안해줘")
        ]
        case "오늘 요약", "지난 7일 회고", "지난 30일 회고": [
            ("완료 흐름", "\(context)에서 잘 이어간 작업을 알려줘"),
            ("놓친 작업", "\(context)에서 놓친 작업의 공통점을 찾아줘"),
            ("다음 계획", "\(context) 내용을 바탕으로 다음 계획을 제안해줘")
        ]
        case "설정": [
            ("권한 확인", "Agent가 사용하는 정보를 알려줘"),
            ("요약 설정", "오늘 요약을 간단하게 설정해줘"),
            ("자동화 확인", "반복 일정 실행 전에 무엇을 확인하는지 알려줘")
        ]
        default: [
            ("오늘 요약", "오늘 일정 핵심만 요약해줘"),
            ("새 일정", "오늘 빈 시간에 집중 일정 1시간 제안해줘"),
            ("미완료 정리", "남은 할 일을 어떻게 처리할지 물어봐줘")
        ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("빠른 요청")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoTheme.secondaryInk)

            VStack(spacing: 0) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { index, item in
                    Button { onSelect(item.1) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MemdoTheme.brand)
                                .frame(width: MemdoMetrics.rowLeadingWidth, height: MemdoMetrics.touchTarget)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.0)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.1)
                                    .font(.caption)
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

private struct AgentResponse: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Agent 초안", systemImage: "checkmark.shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemdoTheme.brand)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MemdoTheme.ink)
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(MemdoTheme.brand)
                .frame(width: 3)
        }
    }
}

private struct AgentComposer: View {
    @Binding var text: String
    let onSend: () -> Void

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Agent에게 요청", text: $text)
                .onSubmit(onSend)
                .padding(.leading, 12)
                .frame(minHeight: MemdoMetrics.touchTarget)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isEmpty ? MemdoTheme.secondaryInk : MemdoTheme.brand)
                    .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
            .accessibilityLabel("요청 보내기")
        }
        .padding(4)
        .memdoFloatingSurface(cornerRadius: MemdoMetrics.groupRadius)
    }
}
