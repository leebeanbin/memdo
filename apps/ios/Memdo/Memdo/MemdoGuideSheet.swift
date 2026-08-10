import SwiftUI
import WidgetKit

struct MemdoGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MemdoSession.self) private var session
    @AppStorage(
        MemdoWidgetStorage.hideContentKey,
        store: UserDefaults(suiteName: MemdoWidgetStorage.suiteName)
    ) private var hideWidgetContent = false
    @State private var showsWallpaperPreview = false
    let onStartCoachMarkTour: (CoachMarkTour) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("화면 둘러보기") {
                    Button { start(.app) } label: {
                        LabeledContent("앱 둘러보기", value: "6단계")
                    }
                    Button { start(.settings) } label: {
                        LabeledContent("설정 둘러보기", value: "3단계")
                    }
                }

                Section("일정 사용법") {
                    guideRow("날짜를 누르면 그날 일정만 보기", systemImage: "calendar")
                    guideRow("날짜를 길게 눌러 일정 추가", systemImage: "calendar.badge.plus")
                    guideRow("Agent 요청은 확인한 뒤 일정에 반영", systemImage: "sparkles")
                }

                Section("홈·잠금화면 위젯") {
                    guideStep(1, "홈 화면이나 잠금화면을 길게 누르기")
                    guideStep(2, "위젯 추가에서 Memdo 검색")
                    guideStep(3, "원하는 크기를 선택하고 배치")
                }

                Section {
                    Toggle("모든 Memdo 위젯에서 일정명 가리기", isOn: $hideWidgetContent)
                        .memdoToggle()
                    Text("켜면 시간과 개수는 유지하고 제목만 ‘비공개 일정’으로 표시해요. 잠금 중 노출 여부는 iPhone의 Face ID 및 암호 설정도 함께 따릅니다.")
                        .font(.footnote)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                } header: {
                    Text("위젯 개인정보")
                }

                Section {
                    guideStep(1, "미리보기에서 스타일을 고르고 ‘사진에 저장’")
                    guideStep(2, "단축어 앱에서 ‘Memdo 달력 배경화면 만들기’ 액션 추가")
                    guideStep(3, "‘배경화면 사진 설정’과 연결해 매일 자동 실행")
                    Button { showsWallpaperPreview = true } label: {
                        LabeledContent("달력 배경화면 미리보기", value: "열기")
                    }
                } header: {
                    Text("전체 달력 배경화면")
                } footer: {
                    Text("설정 > 위젯에서도 언제든 열 수 있어요.")
                }
            }
            .memdoSystemList()
            .navigationTitle("Memdo 시작 가이드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(isPresented: $showsWallpaperPreview) {
                WallpaperPreviewSheet()
            }
        }
        .memdoSheetPresentation([.large])
        .onChange(of: hideWidgetContent) { _, value in
            WidgetCenter.shared.reloadAllTimelines()
            guard session.preferencesStore?.preferences?.hideWidgetContent != value else { return }
            Task { await session.preferencesStore?.update { $0.hideWidgetContent = value } }
        }
    }

    private func guideRow(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    private func guideStep(_ number: Int, _ title: String) -> some View {
        Label(title, systemImage: "\(number).circle")
    }

    private func start(_ tour: CoachMarkTour) {
        dismiss()
        onStartCoachMarkTour(tour)
    }
}
