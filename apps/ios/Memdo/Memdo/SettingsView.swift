import SwiftUI

struct SettingsView: View {
    @Environment(MemdoSession.self) private var session
    @State private var dailySummary = true
    @State private var notifications = true
    @State private var summaryTime = Calendar.current.date(from: DateComponents(hour: 21, minute: 30)) ?? .now
    @State private var promptTime = Calendar.current.date(from: DateComponents(hour: 9)) ?? .now
    @State private var briefingKeywords: Set<String> = ["AI", "제품 디자인"]
    @State private var customKeywords: [String] = []
    @State private var presentedSheet: SettingsSheet?

    var body: some View {
        MemdoPage(title: "설정", subtitle: "Memdo를 나에게 맞게 조정하세요", eyebrow: "나만의 Memdo") {
            SettingsGroup(title: "하루") {
                Toggle("오늘 요약", isOn: $dailySummary)
                    .memdoSettingsRow()
                if dailySummary {
                    Divider()
                    SettingsTimePicker(title: "요약 시간", selection: $summaryTime)
                }
                Divider()
                SettingsTimePicker(title: "계획 알림", selection: $promptTime)
                Divider()
                Toggle("알림", isOn: $notifications)
                    .memdoSettingsRow()
                Divider()
                Button { presentedSheet = .briefingKeywords } label: {
                    SettingsDisclosureRow(title: "브리핑 키워드", value: "\(briefingKeywords.count)개 선택")
                }
                .buttonStyle(.plain)
            }

            SettingsGroup(
                title: "내 Agent 연결",
                subtitle: "서비스는 MCP 도구로 연결되고, 실행은 항상 내 확인을 거쳐요."
            ) {
                Button { presentedSheet = .googleCalendar } label: {
                    AgentConnectionRow(
                        icon: .asset("GoogleCalendar"),
                        title: "Google Calendar",
                        capability: "일정 읽기 · 승인 후 쓰기",
                        status: "미연결",
                        badge: "MCP"
                    )
                }
                .buttonStyle(.plain)
                Divider()
                Button { presentedSheet = .slack } label: {
                    AgentConnectionRow(
                        icon: .asset("Slack"),
                        title: "Slack",
                        capability: "요약 전송 · 알림 예약",
                        status: "미연결",
                        badge: "MCP"
                    )
                }
                .buttonStyle(.plain)
                Divider()
                Button { presentedSheet = .aiConsent } label: {
                    AgentConnectionRow(
                        icon: .system("sparkles"),
                        title: "Memdo Agent",
                        capability: "일정 제목 · 시간만 사용",
                        status: "범위 설정"
                    )
                }
                .buttonStyle(.plain)
                Divider()
                Button { presentedSheet = .privacy } label: {
                    AgentConnectionRow(
                        icon: .system("hand.raised.fill"),
                        title: "데이터 관리",
                        capability: "보관 · 철회 · 연결 해제",
                        status: "확인"
                    )
                }
                .buttonStyle(.plain)
            }

            SettingsGroup(title: "계정") {
                Button {
                    Task { await session.signOut() }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.accountLabel)
                                .font(.subheadline.weight(.semibold))
                            Text("이 기기의 세션을 종료합니다")
                                .font(.caption)
                                .foregroundStyle(MemdoTheme.secondaryInk)
                        }
                        Spacer()
                        Text("로그아웃")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MemdoTheme.secondaryInk)
                    }
                    .memdoSettingsRow()
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
            }

        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .aiConsent:
                AIConsentSheet()
            case .briefingKeywords:
                BriefingKeywordsSheet(
                    selectedKeywords: $briefingKeywords,
                    customKeywords: $customKeywords
                )
            case .privacy:
                PrivacySheet()
            case .slack:
                SlackConnectionSheet()
            case .googleCalendar:
                GoogleCalendarConnectionSheet()
            }
        }
        .sensoryFeedback(.selection, trigger: briefingKeywords)
    }
}

private enum ConnectionIcon {
    case asset(String)
    case system(String)
}

private struct ConnectionMark: View {
    let icon: ConnectionIcon

    var body: some View {
        Group {
            switch icon {
            case .asset(let name):
                Image(name)
                    .resizable()
                    .scaledToFit()
            case .system(let name):
                Image(systemName: name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MemdoTheme.brand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MemdoTheme.brandSoft)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct AgentConnectionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: ConnectionIcon
    let title: String
    let capability: String
    let status: String
    var badge: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ConnectionMark(icon: icon)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let badge {
                        ConnectionBadge(title: badge)
                    }
                }
                Text(capability)
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
                if dynamicTypeSize.isAccessibilitySize {
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }

            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(MemdoTheme.secondaryInk)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 6)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(capability), \(status)")
    }
}

private struct ConnectionBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(MemdoTheme.brand)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(MemdoTheme.brandSoft, in: Capsule())
    }
}

private struct SettingsDisclosureRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if dynamicTypeSize.isAccessibilitySize {
                    Text(value)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(value)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(MemdoTheme.secondaryInk)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .memdoSettingsRow()
    }
}

private struct SettingsTimePicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    @Binding var selection: Date

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                    DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
            }
        }
        .memdoSettingsRow()
    }
}

private enum SettingsSheet: String, Identifiable {
    case aiConsent
    case briefingKeywords
    case googleCalendar
    case privacy
    case slack
    var id: String { rawValue }
}

private struct BriefingKeywordsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedKeywords: Set<String>
    @Binding var customKeywords: [String]
    @State private var draft = ""

    private let suggestedKeywords = ["AI", "SwiftUI", "제품 디자인", "서울 로컬", "스타트업"]

    private var keywordOptions: [String] {
        suggestedKeywords + customKeywords.filter { !suggestedKeywords.contains($0) }
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddKeyword: Bool {
        !normalizedDraft.isEmpty
            && normalizedDraft.count <= 30
            && selectedKeywords.count < 5
            && !keywordOptions.contains { $0.localizedCaseInsensitiveCompare(normalizedDraft) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MemdoMetrics.sectionSpacing) {
                    Text("오늘의 브리핑에서 살펴볼 주제를 최대 5개 선택하세요.")
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.secondaryInk)

                    HStack(spacing: 8) {
                        TextField("키워드 입력", text: $draft)
                            .submitLabel(.done)
                            .onSubmit(addKeyword)
                        Button(action: addKeyword) {
                            MemdoIconButtonLabel(systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAddKeyword)
                        .accessibilityLabel("브리핑 키워드 추가")
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .frame(minHeight: MemdoMetrics.touchTarget)
                    .memdoFloatingSurface(radius: 22)

                    MemdoSection(title: "키워드", trailing: "\(selectedKeywords.count)/5") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(keywordOptions, id: \.self) { keyword in
                                MemdoChoiceButton(
                                    title: keyword,
                                    isSelected: selectedKeywords.contains(keyword),
                                    action: { toggleKeyword(keyword) }
                                )
                            }
                        }
                    }
                }
                .padding(MemdoMetrics.pagePadding)
            }
            .background(MemdoTheme.background)
            .navigationTitle("브리핑 키워드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.medium, .large])
    }

    private func addKeyword() {
        guard canAddKeyword else { return }
        customKeywords.append(normalizedDraft)
        selectedKeywords.insert(normalizedDraft)
        draft = ""
    }

    private func toggleKeyword(_ keyword: String) {
        if selectedKeywords.contains(keyword) {
            selectedKeywords.remove(keyword)
        } else if selectedKeywords.count < 5 {
            selectedKeywords.insert(keyword)
        }
    }
}

private struct GoogleCalendarConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MCPToolIdentityRow(
                        icon: .asset("GoogleCalendar"),
                        title: "Google Calendar",
                        summary: "내 Agent가 일정 문맥을 읽고 변경안을 만들어요."
                    )
                } header: {
                    Text("Agent MCP 도구")
                }
                Section("연결하면 가능한 일") {
                    Label("바쁜 시간만 확인해 일정 추천", systemImage: "clock.badge.checkmark")
                    Label("선택한 캘린더 일정 가져오기", systemImage: "calendar")
                    Label("승인한 일정만 생성·수정", systemImage: "checkmark.shield")
                }
                Section("권한 원칙") {
                    Label("기본은 읽기 전용", systemImage: "eye")
                    Label("쓰기 권한은 필요할 때 별도 요청", systemImage: "square.and.pencil")
                }
                Section {
                    Button("Google Calendar 연결") {}
                        .disabled(true)
                } footer: {
                    Text("Google OAuth 클라이언트와 서버 콜백을 등록한 뒤 활성화돼요.")
                }
            }
            .memdoSystemList()
            .navigationTitle("Google Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
    }
}

private struct SlackConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MCPToolIdentityRow(
                        icon: .asset("Slack"),
                        title: "Slack",
                        summary: "내 Agent가 승인된 요약과 알림만 전송해요."
                    )
                } header: {
                    Text("Agent MCP 도구")
                }
                Section("MVP에서 실제 지원") {
                    LabeledContent("일정·오늘 요약 보내기", value: "chat.postMessage")
                    LabeledContent("정한 시간에 알림 예약", value: "chat.scheduleMessage")
                    LabeledContent("/memdo add로 할 일 초안", value: "commands")
                }
                Section("요청 권한") {
                    LabeledContent("메시지 전송", value: "chat:write")
                    LabeledContent("공개 채널 선택", value: "channels:read")
                    LabeledContent("명령 실행", value: "commands")
                }
                Section("자동으로 하지 않는 일") {
                    Label("채널 기록·DM을 읽지 않음", systemImage: "lock")
                    Label("전송 전 채널과 내용을 확인", systemImage: "checkmark.shield")
                    Label("개인 일정은 기본 공유 안 함", systemImage: "person.crop.circle.badge.xmark")
                }
                Section {
                    Button("Slack 연결") {}
                        .disabled(true)
                } footer: {
                    Text("Slack OAuth 앱, /memdo 명령, 서버 콜백을 등록한 뒤 활성화돼요. 비공개 채널은 앱 초대와 groups:read 동의가 추가로 필요해요.")
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
        .memdoSheetPresentation([.large])
    }
}

private struct MCPToolIdentityRow: View {
    let icon: ConnectionIcon
    let title: String
    let summary: String

    var body: some View {
        HStack(spacing: 12) {
            ConnectionMark(icon: icon)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    ConnectionBadge(title: "MCP")
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("기본 보관") {
                    LabeledContent("활성 일정", value: "계정 유지 기간")
                    LabeledContent("삭제 일정", value: "30일")
                    LabeledContent("AI 계획 초안", value: "24시간")
                    LabeledContent("원문 AI 프롬프트", value: "기본 미저장")
                }
                Section("내가 통제하는 정보") {
                    Label("AI·알림·캘린더 동의는 각각 철회", systemImage: "hand.raised")
                    Label("연결 해제 시 외부 토큰 즉시 폐기", systemImage: "key.slash")
                    Label("AI 기록 삭제 요청 제공", systemImage: "trash")
                }
                Section {
                    Text("현재 보존 정책은 출시 전 법률 검토가 필요한 제품 초안이에요.")
                        .font(.footnote)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
            }
            .memdoSystemList()
            .navigationTitle("개인정보 및 데이터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
    }
}

private struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("AI가 보는 정보") {
                    Label("일정 제목", systemImage: "textformat")
                    Label("시작·종료 시간", systemImage: "clock")
                }
                Section("AI가 보지 않는 정보") {
                    Label("위치와 메모", systemImage: "lock")
                    Label("연결하지 않은 외부 데이터", systemImage: "lock")
                }
                Section("실행 원칙") {
                    Label("일정 변경은 확인 후 실행", systemImage: "checkmark.shield")
                }
            }
            .memdoSystemList()
            .navigationTitle("AI 데이터 접근")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        MemdoSection(title: title) {
            VStack(alignment: .leading, spacing: 8) {
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
                VStack(spacing: 0) { content }
                    .padding(.horizontal, 12)
                    .memdoRowGroup()
            }
        }
    }
}
