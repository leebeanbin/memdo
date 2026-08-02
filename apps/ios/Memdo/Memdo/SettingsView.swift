import SwiftUI

struct SettingsView: View {
    @State private var dailySummary = true
    @State private var notifications = true
    @State private var summaryTime = Calendar.current.date(from: DateComponents(hour: 21, minute: 30)) ?? .now
    @State private var promptTime = Calendar.current.date(from: DateComponents(hour: 9)) ?? .now
    @State private var briefingKeywords: Set<String> = ["AI", "제품 디자인"]
    @State private var customKeywords: [String] = []
    @State private var keywordDraft = ""
    @State private var presentedSheet: SettingsSheet?

    private let suggestedKeywords = ["AI", "SwiftUI", "제품 디자인", "서울 로컬", "스타트업"]

    var body: some View {
        MemdoPage(title: "설정", subtitle: "Memdo를 나에게 맞게 조정하세요", eyebrow: "나만의 Memdo") {
            SettingsGroup(title: "하루") {
                Toggle("오늘 요약 받기", isOn: $dailySummary)
                    .memdoSettingsRow()
                Divider()
                SettingsTimePicker(title: "요약 시간", selection: $summaryTime)
                    .disabled(!dailySummary)
                Divider()
                SettingsTimePicker(title: "계획이 없을 때", selection: $promptTime)
            }

            SettingsGroup(title: "연결 및 권한") {
                Button { presentedSheet = .googleCalendar } label: {
                    SettingsDisclosureRow(title: "Google Calendar", value: "연결 안 됨")
                }
                .buttonStyle(.plain)
                Divider()
                Button { presentedSheet = .slack } label: {
                    SettingsDisclosureRow(title: "Slack", value: "연결 안 됨")
                }
                .buttonStyle(.plain)
                Divider()
                Button { presentedSheet = .aiConsent } label: {
                    SettingsDisclosureRow(title: "AI 데이터 접근", value: "일정 제목·시간")
                }
                .buttonStyle(.plain)
                Divider()
                Toggle("알림", isOn: $notifications)
                    .memdoSettingsRow()
            }

            SettingsGroup(title: "브리핑 키워드") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("오늘의 브리핑이 찾아볼 주제를 키워드로 골라요.")
                        .font(.subheadline)
                        .foregroundStyle(MemdoTheme.secondaryInk)

                    HStack(spacing: 8) {
                        TextField("키워드 입력", text: $keywordDraft)
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
                    .frame(minHeight: 52)
                    .background(MemdoTheme.background.opacity(0.78), in: Capsule())
                    .overlay(Capsule().stroke(MemdoTheme.controlOutline.opacity(0.45)))

                    Divider()

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(keywordOptions, id: \.self) { keyword in
                            MemdoChoiceButton(
                                title: keyword,
                                isSelected: briefingKeywords.contains(keyword),
                                action: { toggleKeyword(keyword) }
                            )
                        }
                    }

                    Text("\(briefingKeywords.count)/5 · 선택한 단어는 브리핑 검색과 정렬에만 사용해요.")
                        .font(.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                }
                .padding(.vertical, 14)
            }

            SettingsGroup(title: "개인정보") {
                Button { presentedSheet = .privacy } label: {
                    SettingsDisclosureRow(title: "개인정보 및 데이터", value: "보관·철회")
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .aiConsent:
                AIConsentSheet()
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

    private var keywordOptions: [String] {
        suggestedKeywords + customKeywords.filter { !suggestedKeywords.contains($0) }
    }

    private var normalizedDraft: String {
        keywordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddKeyword: Bool {
        !normalizedDraft.isEmpty
            && normalizedDraft.count <= 30
            && briefingKeywords.count < 5
            && !keywordOptions.contains { $0.localizedCaseInsensitiveCompare(normalizedDraft) == .orderedSame }
    }

    private func addKeyword() {
        guard canAddKeyword else { return }
        customKeywords.append(normalizedDraft)
        briefingKeywords.insert(normalizedDraft)
        keywordDraft = ""
    }

    private func toggleKeyword(_ keyword: String) {
        if briefingKeywords.contains(keyword) {
            briefingKeywords.remove(keyword)
        } else if briefingKeywords.count < 5 {
            briefingKeywords.insert(keyword)
        }
    }
}

private struct SettingsDisclosureRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
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
    case googleCalendar
    case privacy
    case slack
    var id: String { rawValue }
}

private struct GoogleCalendarConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
            .scrollContentBackground(.hidden)
            .background(MemdoTheme.background)
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
            .scrollContentBackground(.hidden)
            .background(MemdoTheme.background)
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
            .scrollContentBackground(.hidden)
            .background(MemdoTheme.background)
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
            .scrollContentBackground(.hidden)
            .background(MemdoTheme.background)
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
    @ViewBuilder let content: Content

    var body: some View {
        MemdoSection(title: title) {
            VStack(spacing: 0) { content }
                .padding(.horizontal, 12)
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }
                .memdoGlassPanel()
        }
    }
}
