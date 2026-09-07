import SwiftUI

struct SlackConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    // Keychain-backed (see SlackNotifier) rather than @AppStorage -- a Slack
    // Incoming Webhook URL is a bearer credential, not a plain preference.
    @State private var webhookURL = ""
    @State private var draftURL = ""
    @State private var isTesting = false
    @State private var testResult: SlackTestResult?
    @State private var showDisconnectConfirm = false

    private var isConnected: Bool { !webhookURL.isEmpty }
    private var maskedURL: String {
        guard let host = URL(string: webhookURL)?.host else { return webhookURL }
        return "hooks.slack.com/…/\(String(webhookURL.suffix(8)))"
            .replacingOccurrences(of: host, with: "hooks.slack.com")
    }
    private var canConnect: Bool {
        draftURL.hasPrefix("https://hooks.slack.com/services/")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MCPToolIdentityRow(
                        icon: .asset("Slack"),
                        title: "Slack",
                        summary: "선택한 채널로 일정 알림을 보내요."
                    )
                } header: {
                    Text("Slack 알림")
                }
                Section("연결하면 가능한 일") {
                    Label("새 일정 만들면 채널에 알림", systemImage: "calendar.badge.plus")
                    Label("할 일 완료하면 채널에 알림", systemImage: "checkmark.circle")
                    Label("테스트 메시지로 연결 확인", systemImage: "paperplane")
                }
                Section("자동으로 하지 않는 일") {
                    Label("채널 기록·DM을 읽지 않음", systemImage: "lock")
                    Label("전송 전 채널과 내용을 확인", systemImage: "checkmark.shield")
                    Label("개인 일정은 기본 공유 안 함", systemImage: "person.crop.circle.badge.xmark")
                }

                if isConnected {
                    Section("연결된 채널") {
                        LabeledContent("Webhook URL") {
                            Text(maskedURL)
                                .font(MemdoTypography.caption.monospacedDigit())
                                .foregroundStyle(MemdoTheme.secondaryInk)
                                .lineLimit(1)
                        }
                        Button {
                            Task { await sendTestMessage() }
                        } label: {
                            if isTesting {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("전송 중")
                                }
                            } else {
                                Text("테스트 메시지 보내기")
                            }
                        }
                        .disabled(isTesting)
                    }
                    if let result = testResult {
                        Section {
                            Label(result.message, systemImage: result.icon)
                                .foregroundStyle(result.isSuccess ? .green : .red)
                                .font(MemdoTypography.caption)
                        }
                    }
                    Section {
                        Button("연결 해제", role: .destructive) {
                            showDisconnectConfirm = true
                        }
                    }
                } else {
                    Section {
                        TextField("https://hooks.slack.com/services/…", text: $draftURL)
                            .font(MemdoTypography.caption.monospacedDigit())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("연결") {
                            webhookURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            SlackNotifier.webhookURL = webhookURL
                            draftURL = ""
                        }
                        .disabled(!canConnect)
                    } header: {
                        Text("Incoming Webhook URL")
                    } footer: {
                        Text("Slack 워크스페이스 설정 → 앱 → Incoming Webhooks에서 URL을 발급받아 붙여넣으세요.")
                    }
                }
            }
            .memdoSystemList()
            .navigationTitle("Slack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .confirmationDialog("Slack 연결을 해제할까요?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("연결 해제", role: .destructive) {
                webhookURL = ""
                SlackNotifier.webhookURL = ""
                testResult = nil
            }
            Button("취소", role: .cancel) {}
        }
        .memdoSheetPresentation([.large])
        .task { webhookURL = SlackNotifier.webhookURL }
    }

    private func sendTestMessage() async {
        guard let url = URL(string: webhookURL) else { return }
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            let ok = try await SlackNotifier.sendTest(to: url)
            testResult = ok
                ? SlackTestResult(isSuccess: true, message: "Slack 채널에 메시지를 전달했어요.", icon: "checkmark.circle.fill")
                : SlackTestResult(isSuccess: false, message: "전송에 실패했어요. URL을 확인해 주세요.", icon: "exclamationmark.circle.fill")
        } catch {
            testResult = SlackTestResult(isSuccess: false, message: "네트워크 오류: \(error.localizedDescription)", icon: "wifi.exclamationmark")
        }
    }
}

private struct SlackTestResult {
    let isSuccess: Bool
    let message: String
    let icon: String
}
