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

                Section {
                    guideRow("날짜를 누르면 그날 일정만 보기", systemImage: "calendar")
                    guideRow("날짜를 길게 눌러 일정 추가", systemImage: "calendar.badge.plus")
                    guideRow("새 일정 시트에서 분류를 눌러 할 일·이벤트·운동 선택", systemImage: "tray.full")
                    guideRow("분류 하단 색상 점으로 일정 색상 지정", systemImage: "paintpalette")
                    guideRow("Agent 요청은 확인한 뒤 일정에 반영", systemImage: "sparkles")
                } header: {
                    Text("일정 사용법")
                }

                Section {
                    guideRow("분류 메뉴 하단 '카테고리 추가'로 나만의 카테고리 만들기", systemImage: "tag")
                    guideRow("이름·이모지·색상·종류를 자유롭게 설정", systemImage: "slider.horizontal.3")
                } header: {
                    Text("사용자 정의 카테고리")
                }

                Section {
                    guideRow("시작 4시간 전 Dynamic Island에 일정이 자동 표시됨", systemImage: "oval.tophalf.filled")
                    guideRow("시작 전: 카운트다운, 진행 중: 종료까지 남은 시간, 완료: 체크 표시", systemImage: "clock.badge.checkmark")
                    guideRow("Dynamic Island를 꾹 누르면 제목·시간 전체 보기", systemImage: "hand.tap")
                    guideRow("앱 없이도 화면 상단에서 현재 일정 확인 가능", systemImage: "iphone")
                } header: {
                    Text("Dynamic Island 일정 알림")
                } footer: {
                    Text("앱이 포그라운드에 오면 자동으로 활성화되며, 일정이 없을 때는 표시되지 않아요.")
                }

                Section("홈·잠금화면 위젯") {
                    guideStep(1, "홈 화면이나 잠금화면을 길게 누르기")
                    guideStep(2, "위젯 추가에서 Memdo 검색")
                    guideStep(3, "원하는 크기를 선택하고 배치")
                }

                Section {
                    Toggle("모든 Memdo 위젯에서 일정명 가리기", isOn: $hideWidgetContent)
                        .memdoToggle()
                    Text("켜면 시간과 개수는 유지하고 제목만 '비공개 일정'으로 표시해요. 잠금 중 노출 여부는 iPhone의 Face ID 및 암호 설정도 함께 따릅니다.")
                        .font(.footnote)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                } header: {
                    Text("위젯 개인정보")
                }

                Section {
                    guideStep(1, "미리보기에서 스타일을 고르고 '사진에 저장'")
                    guideStep(2, "단축어 앱에서 'Memdo 달력 배경화면 만들기' 액션 추가")
                    guideStep(3, "'배경화면 사진 설정'과 연결해 매일 자동 실행")
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
        }
        .memdoSheetPresentation([.large])
        .fullScreenCover(isPresented: $showsWallpaperPreview) {
            WallpaperPreviewSheet { showsWallpaperPreview = false }
        }
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
