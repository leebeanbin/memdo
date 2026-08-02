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
                    .background(.bar)
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
        response = "‘\(prompt)’ 요청을 확인했어요. 일정 변경안은 실행 전에 시작·종료·알림을 다시 보여드릴게요."
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
        VStack(alignment: .leading, spacing: 5) {
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
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MemdoTheme.brand)
                            Text(item.0)
                                .font(.subheadline.weight(.semibold))
                            Text(item.1)
                                .font(.caption)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(MemdoTheme.ink)
                        .frame(minHeight: MemdoMetrics.touchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < prompts.count - 1 {
                        Divider()
                    }
                }
            }
            .overlay(alignment: .bottom) { Divider() }
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
                MemdoIconButtonLabel(systemImage: "arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(isEmpty)
            .accessibilityLabel("요청 보내기")
        }
        .padding(4)
        .memdoFloatingSurface(radius: 20)
    }
}
