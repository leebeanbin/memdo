import SwiftUI

enum CoachMarkTour {
    case app
    case settings

    var steps: [CoachMarkStep] {
        switch self {
        case .app:
            [
                .init(.todayOverview, .today, "오늘", "날짜와 완료 현황을 한눈에 확인해요."),
                .init(.todayDates, .today, "날짜 이동", "날짜를 누르거나 좌우로 밀어 다른 날을 확인해요. 날짜를 길게 누르면 바로 일정을 추가할 수 있어요."),
                .init(.todaySchedule, .today, "일정", "빈 날은 바로 계획하고, 일정은 완료하거나 상세를 열 수 있어요."),
                .init(.todayBriefing, .today, "오늘의 브리핑", "관심사와 일정에 영향을 주는 정보만 짧게 정리해요."),
                .init(.calendarOverview, .calendar, "캘린더", "월간 흐름을 보고 검색과 필터로 필요한 일정만 찾을 수 있어요."),
                .init(.agentTab, .today, "Memdo Agent", "하단 Agent를 누르면 현재 화면의 문맥을 유지한 채 요청할 수 있어요.")
            ]
        case .settings:
            [
                .init(.settingsDay, .settings, "하루와 알림", "요약 시간과 계획 알림을 내 생활에 맞게 조정해요."),
                .init(.settingsWidget, .settings, "위젯과 배경화면", "달력 배경화면을 미리 보고 사진으로 저장할 수 있어요."),
                .init(.settingsConnections, .settings, "연결과 개인정보", "Agent가 사용할 서비스와 데이터 범위를 각각 선택해요.")
            ]
        }
    }
}

enum CoachMarkTarget: Hashable {
    case todayOverview
    case todayDates
    case todaySchedule
    case todayBriefing
    case calendarOverview
    case agentTab
    case settingsDay
    case settingsWidget
    case settingsConnections
}

struct CoachMarkStep {
    let target: CoachMarkTarget
    let tab: AppTab
    let title: String
    let message: String

    init(_ target: CoachMarkTarget, _ tab: AppTab, _ title: String, _ message: String) {
        self.target = target
        self.tab = tab
        self.title = title
        self.message = message
    }
}

private struct CoachMarkTargetKey: PreferenceKey {
    static let defaultValue: [CoachMarkTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [CoachMarkTarget: Anchor<CGRect>],
        nextValue: () -> [CoachMarkTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func coachMarkTarget(_ target: CoachMarkTarget) -> some View {
        anchorPreference(key: CoachMarkTargetKey.self, value: .bounds) { [target: $0] }
    }

    func coachMarkOverlay(
        step: CoachMarkStep?,
        index: Int,
        count: Int,
        onPrevious: @escaping (Int) -> Void,
        onNext: @escaping (Int) -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        overlayPreferenceValue(CoachMarkTargetKey.self) { targets in
            // Cover the full screen: without ignoresSafeArea the dimming stops
            // at the safe-area edges, leaving undimmed strips above and below.
            GeometryReader { proxy in
                if let step, let frame = frame(for: step.target, targets: targets, proxy: proxy) {
                    CoachMarkOverlay(
                        step: step,
                        index: index,
                        count: count,
                        targetFrame: frame,
                        canvasSize: proxy.size,
                        onPrevious: onPrevious,
                        onNext: onNext,
                        onSkip: onSkip
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    private func frame(
        for target: CoachMarkTarget,
        targets: [CoachMarkTarget: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> CGRect? {
        if let anchor = targets[target] {
            let resolved = proxy[anchor]
            let viewport = CGRect(origin: .zero, size: proxy.size)
            return resolved.intersects(viewport) ? resolved : nil
        }
        if target == .agentTab {
            let width: CGFloat = 56
            let height: CGFloat = 44
            return CGRect(
                x: proxy.size.width * 0.815 - width / 2,
                y: proxy.size.height - 74,
                width: width,
                height: height
            )
        }
        return nil
    }
}

private struct CoachMarkOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isFocused: Bool
    let step: CoachMarkStep
    let index: Int
    let count: Int
    let targetFrame: CGRect
    let canvasSize: CGSize
    let onPrevious: (Int) -> Void
    let onNext: (Int) -> Void
    let onSkip: () -> Void

    private var spotlightFrame: CGRect {
        targetFrame
            .insetBy(dx: -8, dy: -8)
            .intersection(CGRect(origin: .zero, size: canvasSize).insetBy(dx: 8, dy: 8))
    }

    var body: some View {
        ZStack {
            spotlight
            if step.target == .agentTab {
                VStack {
                    Spacer()
                    coachCard
                        .overlay(alignment: .bottomLeading) {
                            CoachMarkPointer()
                                .fill(.regularMaterial)
                                .frame(width: 18, height: 10)
                                .offset(
                                    x: spotlightFrame.midX - MemdoMetrics.pagePadding - 9,
                                    y: 9
                                )
                        }
                }
                .padding(.horizontal, MemdoMetrics.pagePadding)
                .padding(.bottom, canvasSize.height - spotlightFrame.minY + 16)
            } else {
                VStack {
                    if spotlightFrame.midY < canvasSize.height / 2 { Spacer() }
                    coachCard
                    if spotlightFrame.midY >= canvasSize.height / 2 { Spacer() }
                }
                .padding(.horizontal, MemdoMetrics.pagePadding)
                .padding(.top, 54)
                .padding(.bottom, 100)
            }
        }
        .tint(MemdoTheme.accent)
        .accessibilityAddTraits(.isModal)
        .onAppear { isFocused = true }
        .transition(reduceMotion ? .identity : .opacity)
        .zIndex(100)
    }

    private var spotlight: some View {
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: canvasSize))
                path.addRoundedRect(in: spotlightFrame, cornerSize: CGSize(width: 18, height: 18))
            }
            .fill(.black.opacity(0.7), style: FillStyle(eoFill: true))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 1)
                .frame(width: spotlightFrame.width, height: spotlightFrame.height)
                .position(x: spotlightFrame.midX, y: spotlightFrame.midY)
        }
        .accessibilityHidden(true)
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(index + 1) / \(count)")
                    .font(MemdoTypography.captionEmphasis)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("건너뛰기", action: onSkip)
                    .font(MemdoTypography.captionEmphasis)
            }
            Text(step.title)
                .font(MemdoTypography.sectionTitle)
                .accessibilityFocused($isFocused)
            Text(step.message)
                .font(MemdoTypography.subtitle)
                .foregroundStyle(.secondary)
            HStack {
                if index > 0 {
                    Button("이전") { onPrevious(index) }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if index == count - 1 {
                    Button { onNext(index) } label: {
                        Text("완료")
                            .foregroundStyle(MemdoTheme.onAccent)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("둘러보기 완료")
                } else {
                    Button { onNext(index) } label: {
                        Text("다음")
                            .foregroundStyle(MemdoTheme.onAccent)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("다음 단계")
                }
            }
        }
        .padding(16)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: MemdoMetrics.groupRadius, style: .continuous)
        )
    }
}

private struct CoachMarkPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
