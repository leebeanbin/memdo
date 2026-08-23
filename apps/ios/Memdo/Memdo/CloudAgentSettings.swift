import SwiftUI

/// Not private -- AssistantView presents this directly when the cloud Agent
/// path is needed but no OpenRouter key is connected yet, instead of only
/// erroring after a wasted round trip and pointing the user back to Settings.
struct CloudAgentConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var isConnected: Bool?
    @State private var draftKey = ""
    @State private var isBusy = false
    @State private var isLoadingDetails = false
    @State private var errorMessage: String?
    @State private var detailErrorMessage: String?
    @State private var showDisconnectConfirm = false
    @State private var models: [AgentModelDTO] = []
    @State private var usage: AgentUsageResponseDTO?
    @State private var selectedModel = CloudAgentModelPreference.selected
        ?? CloudAgentModelPreference.defaultID
    @AppStorage("memdo.v1.agentShowsActualCost") private var showsActualCost = false

    private var canConnect: Bool {
        draftKey.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
    }

    var body: some View {
        NavigationStack {
            Group {
                if isConnected == false {
                    disconnectedContent
                } else if isConnected == nil {
                    ProgressView("연결 상태 확인 중")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                    Section {
                        LabeledContent("상태", value: connectionStatus)
                    } header: {
                        Label("OpenRouter", systemImage: "cloud")
                    }
                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.circle")
                                .font(MemdoTypography.caption)
                                .foregroundStyle(MemdoTheme.destructive)
                        }
                    }

                    Section {
                        if models.isEmpty {
                            loadingRow(isLoadingDetails ? "모델을 불러오는 중" : "모델을 불러오지 못했어요")
                        } else {
                            ForEach(models) { model in
                                modelRow(model)
                            }
                        }
                    } header: {
                        Text("모델")
                    } footer: {
                        Text("가격은 OpenRouter의 현재 1M 토큰당 요금이에요.")
                    }

                    Section("최근 30일") {
                        Toggle("실제 비용 표시", isOn: $showsActualCost)
                            .memdoToggle()
                        if let usage {
                            LabeledContent("요청", value: "\(usage.totalRequests)회")
                            if showsActualCost {
                                LabeledContent("비용", value: usageCost(usage.totalCostUsd))
                                    .monospacedDigit()
                            }
                            ForEach(usage.recent) { item in
                                usageRow(item)
                            }
                        } else {
                            loadingRow(isLoadingDetails ? "사용량을 불러오는 중" : "사용량을 불러오지 못했어요")
                        }
                    }

                    if let detailErrorMessage {
                        Section {
                            Label(detailErrorMessage, systemImage: "exclamationmark.circle")
                                .font(MemdoTypography.caption)
                                .foregroundStyle(MemdoTheme.destructive)
                            Button("다시 시도") {
                                Task { await loadConnectedContent() }
                            }
                            .buttonStyle(MemdoSecondaryActionButtonStyle())
                            .disabled(isLoadingDetails)
                        }
                    }
                    }
                    .memdoSystemList()
                }
            }
            .background(MemdoTheme.background)
            .navigationTitle("클라우드 모델")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isConnected == true {
                        Button {
                            showDisconnectConfirm = true
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("연결 관리")
                        .disabled(isBusy)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .confirmationDialog(
            "OpenRouter 연결을 해제할까요?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("연결 해제", role: .destructive) { Task { await disconnect() } }
            Button("취소", role: .cancel) {}
        }
        .memdoSheetPresentation([.height(350), .large])
        .task { await loadStatus() }
    }

    private var disconnectedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
                HStack(spacing: 12) {
                    Image(systemName: "cloud")
                        .font(.body.weight(.medium))
                        .frame(width: 36, height: 36)
                        .background(MemdoTheme.accentSoft, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenRouter")
                            .font(MemdoTypography.sectionTitle)
                        Text("내 API 키로 클라우드 모델 사용")
                            .font(MemdoTypography.caption)
                            .foregroundStyle(MemdoTheme.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Text("미연결")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API 키")
                        .font(MemdoTypography.captionEmphasis)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                    HStack(spacing: 8) {
                        SecureField("sk-or-v1-…", text: $draftKey)
                            .font(MemdoTypography.subtitle.monospacedDigit())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
                            .background(
                                MemdoTheme.surface,
                                in: RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: MemdoMetrics.fieldRadius, style: .continuous)
                                    .stroke(MemdoTheme.controlOutline, lineWidth: 0.5)
                            }
                        pasteButton
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(MemdoTypography.caption)
                            .foregroundStyle(MemdoTheme.destructive)
                    }
                }

                connectButton

                Label("키는 암호화해 저장하며 앱에 다시 표시하지 않아요.", systemImage: "lock")
                    .font(MemdoTypography.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .padding(MemdoMetrics.pagePadding)
        }
    }

    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { values in
            draftKey = values.first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.roundedRectangle)
        .frame(width: MemdoMetrics.touchTarget, height: MemdoMetrics.touchTarget)
        .accessibilityLabel("API 키 붙여넣기")
    }

    private var connectButton: some View {
        Button {
            Task { await connect() }
        } label: {
            if isBusy {
                ProgressView()
            } else {
                Text("OpenRouter 연결")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle)
        .tint(MemdoTheme.accent)
        .foregroundStyle(MemdoTheme.onAccent)
        .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
        .disabled(!canConnect || isBusy)
    }

    private var connectionStatus: String {
        guard let isConnected else { return "확인 중" }
        return isConnected ? "연결됨" : "미연결"
    }

    @ViewBuilder
    private func loadingRow(_ title: String) -> some View {
        if isLoadingDetails {
            ProgressView(title)
                .frame(minHeight: MemdoMetrics.touchTarget)
        } else {
            Label(title, systemImage: "exclamationmark.circle")
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(minHeight: MemdoMetrics.touchTarget)
        }
    }

    private func modelRow(_ model: AgentModelDTO) -> some View {
        Button {
            selectedModel = model.id
            CloudAgentModelPreference.selected = model.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedModel == model.id ? "checkmark.circle.fill" : "circle")
                    .font(MemdoTypography.title3)
                    .foregroundStyle(selectedModel == model.id ? MemdoTheme.brand : MemdoTheme.secondaryInk)
                    .frame(width: 24, height: MemdoMetrics.touchTarget)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(MemdoTypography.action)
                        .foregroundStyle(MemdoTheme.ink)
                        .lineLimit(1)
                    Text(modelPrice(model))
                        .font(MemdoTypography.caption2.monospacedDigit())
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: MemdoMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.name), \(modelPrice(model))")
        .accessibilityAddTraits(selectedModel == model.id ? .isSelected : [])
    }

    private func usageRow(_ item: AgentUsageItemDTO) -> some View {
        HStack(spacing: MemdoMetrics.rowSpacing) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(MemdoTheme.secondaryInk)
                .frame(width: 24, height: MemdoMetrics.touchTarget)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(models.first(where: { $0.id == item.model })?.name ?? item.model)
                    .font(MemdoTypography.subtitle)
                    .lineLimit(1)
                Text(usageDate(item.createdAt))
                    .font(MemdoTypography.caption2)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            Spacer(minLength: 8)
            if showsActualCost {
                Text(usageCost(item.costUsd))
                    .font(MemdoTypography.caption2.monospacedDigit())
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
        .frame(minHeight: MemdoMetrics.settingsRowHeight)
    }

    private func loadStatus() async {
        do {
            isConnected = try await scheduleStore.agentKeyConnected()
            if isConnected == true { await loadConnectedContent() }
        } catch {
            isConnected = false
            errorMessage = "연결 상태를 확인하지 못했어요."
        }
    }

    private func connect() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await scheduleStore.saveAgentKey(draftKey.trimmingCharacters(in: .whitespacesAndNewlines))
            draftKey = ""
            isConnected = true
            await loadConnectedContent()
        } catch {
            errorMessage = "연결하지 못했어요. 키를 확인해 주세요."
        }
    }

    private func disconnect() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await scheduleStore.deleteAgentKey()
            isConnected = false
            models = []
            usage = nil
        } catch {
            errorMessage = "연결 해지에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    private func loadConnectedContent() async {
        isLoadingDetails = true
        detailErrorMessage = nil
        defer { isLoadingDetails = false }

        do {
            models = try await scheduleStore.agentModels()
            if !models.contains(where: { $0.id == selectedModel }), let first = models.first {
                selectedModel = first.id
                CloudAgentModelPreference.selected = first.id
            }
        } catch {
            models = []
            detailErrorMessage = "모델 목록을 불러오지 못했어요."
        }

        do {
            usage = try await scheduleStore.agentUsage()
        } catch {
            usage = nil
            detailErrorMessage = [detailErrorMessage, "사용량을 불러오지 못했어요."]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }

    private func modelPrice(_ model: AgentModelDTO) -> String {
        "in \(usd(model.promptPricePerM, digits: 2)) · out \(usd(model.completionPricePerM, digits: 2)) /1M"
    }

    private func usageCost(_ cost: Double) -> String {
        usd(cost, digits: 6)
    }

    private func usd(_ value: Double, digits: Int) -> String {
        "$" + String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, value)
    }

    private func usageDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}
