import Photos
import SwiftUI
import UIKit

/// Persisted styling shared with GenerateWallpaperIntent so the image the
/// Shortcuts action produces matches the last-previewed look.
enum WallpaperStyleStorage {
    static let calendarKey = "wallpaper-calendar-style"
    static let backdropKey = "wallpaper-backdrop-style"
    static let glassKey = "wallpaper-glass-strength"
}

struct WallpaperPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @AppStorage(
        WallpaperStyleStorage.calendarKey,
        store: UserDefaults(suiteName: MemdoWidgetStorage.suiteName)
    ) private var calendarStyle = WallpaperCalendarStyle.label
    @AppStorage(
        WallpaperStyleStorage.backdropKey,
        store: UserDefaults(suiteName: MemdoWidgetStorage.suiteName)
    ) private var backdrop = WallpaperBackdropStyle.aurora
    @AppStorage(
        WallpaperStyleStorage.glassKey,
        store: UserDefaults(suiteName: MemdoWidgetStorage.suiteName)
    ) private var glassStrength = WallpaperGlassStrength.balanced
    @State private var showsDensitySample = true
    @State private var saveState = SaveState.idle

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    // The density sample is a preview-only aid; the saved image uses real
    // schedules only.
    private var previewTitles: [Date: [String]] {
        var titles = WallpaperCanvas.titles(from: scheduleStore.schedules, month: .now)
        guard showsDensitySample else { return titles }
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: .now) else { return titles }
        for (dayNumber, samples) in Self.sampleTitles {
            guard let day = calendar.date(byAdding: .day, value: dayNumber - 1, to: interval.start) else { continue }
            titles[day, default: []].append(contentsOf: samples)
        }
        return titles
    }

    var body: some View {
        NavigationStack {
            WallpaperCanvas(
                month: .now,
                titlesByDay: previewTitles,
                calendarStyle: calendarStyle,
                backdrop: backdrop,
                glassStrength: glassStrength,
                isExport: false
            )
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .aspectRatio(393 / 852, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(.black)
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle("달력 배경화면")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("캘린더", selection: $calendarStyle) {
                            ForEach(WallpaperCalendarStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        Picker("배경", selection: $backdrop) {
                            ForEach(WallpaperBackdropStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        Picker("Glass", selection: $glassStrength) {
                            ForEach(WallpaperGlassStrength.allCases) { strength in
                                Text(strength.title).tag(strength)
                            }
                        }
                        Toggle("밀도 예시", isOn: $showsDensitySample)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("배경화면 시안 설정")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .memdoSheetPresentation([.large])
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button(action: saveToPhotos) {
                Group {
                    switch saveState {
                    case .saving:
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("저장 중")
                        }
                    case .saved:
                        Label("사진에 저장됨", systemImage: "checkmark")
                    case .idle, .failed:
                        Text("사진에 저장")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(saveState == .saving)

            if case .failed(let message) = saveState {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("단축어 앱의 ‘Memdo 달력 배경화면 만들기’ 액션을 ‘배경화면 사진 설정’과 연결하면 매일 자동으로 갱신할 수 있어요.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, MemdoMetrics.pagePadding)
        .padding(.vertical, 12)
        .background(.black)
    }

    private func saveToPhotos() {
        guard saveState != .saving else { return }
        saveState = .saving
        let titles = WallpaperCanvas.titles(from: scheduleStore.schedules, month: .now)
        Task {
            guard let image = WallpaperImageExporter.uiImage(
                month: .now,
                titlesByDay: titles,
                calendarStyle: calendarStyle,
                backdrop: backdrop,
                glassStrength: glassStrength
            ) else {
                saveState = .failed("이미지를 만들지 못했어요.")
                return
            }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveState = .failed("설정에서 사진 추가 권한을 허용해 주세요.")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                saveState = .saved
            } catch {
                saveState = .failed("저장하지 못했어요. 잠시 후 다시 시도해 주세요.")
            }
        }
    }

    private static let sampleTitles: [Int: [String]] = [
        3: ["프로젝트 시작"],
        6: ["디자인 리뷰"],
        9: ["주간 계획", "30분 산책"],
        14: ["고객 미팅"],
        18: ["운동"],
        21: ["팀 회고", "저녁 약속"],
        27: ["제품 리뷰"]
    ]
}

/// Renders the wallpaper canvas into a lock-screen-sized image (393×852 @3x).
@MainActor
enum WallpaperImageExporter {
    static let canvasSize = CGSize(width: 393, height: 852)

    static func uiImage(
        month: Date,
        titlesByDay: [Date: [String]],
        calendarStyle: WallpaperCalendarStyle,
        backdrop: WallpaperBackdropStyle,
        glassStrength: WallpaperGlassStrength
    ) -> UIImage? {
        let renderer = ImageRenderer(
            content: WallpaperCanvas(
                month: month,
                titlesByDay: titlesByDay,
                calendarStyle: calendarStyle,
                backdrop: backdrop,
                glassStrength: glassStrength,
                isExport: true
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
        )
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The wallpaper artwork itself. The preview draws a fake lock-screen clock and
/// quick actions for context; exports keep their layout space empty because the
/// real lock screen provides them.
struct WallpaperCanvas: View {
    let month: Date
    let titlesByDay: [Date: [String]]
    let calendarStyle: WallpaperCalendarStyle
    let backdrop: WallpaperBackdropStyle
    let glassStrength: WallpaperGlassStrength
    let isExport: Bool

    var body: some View {
        ZStack {
            WallpaperBackdrop(style: backdrop)
            VStack(spacing: 0) {
                WallpaperClock(date: month)
                    .opacity(isExport ? 0 : 1)
                Spacer(minLength: 20)
                WallpaperCalendarPanel(
                    month: month,
                    titlesByDay: titlesByDay,
                    calendarStyle: calendarStyle,
                    glassStrength: glassStrength,
                    isExport: isExport
                )
                Spacer(minLength: 18)
                WallpaperSystemActions()
                    .opacity(isExport ? 0 : 1)
            }
            .padding(.top, 36)
            .padding(.bottom, 18)
            .padding(.horizontal, 18)
        }
    }
}

extension WallpaperCanvas {
    /// Day-keyed titles for a month of real schedules, matching the calendar's
    /// per-day occurrence rules (multi-day events appear on every day they span).
    static func titles(from schedules: [ScheduleDetail], month: Date) -> [Date: [String]] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [:] }
        var titles: [Date: [String]] = [:]
        var day = interval.start
        while day < interval.end {
            let dayTitles = schedules
                .filter { !$0.isDone && $0.occurs(on: day) }
                .sorted { $0.timeSortKey(on: day) < $1.timeSortKey(on: day) }
                .map(\.title)
            if !dayTitles.isEmpty { titles[day] = dayTitles }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }
        return titles
    }

    /// Same, but from the widget snapshot — used by GenerateWallpaperIntent,
    /// which runs without a loaded ScheduleStore. Honors the widget privacy
    /// toggle because the intent runs unattended.
    static func titles(
        from snapshot: MemdoWidgetSnapshot,
        month: Date,
        hidesContent: Bool
    ) -> [Date: [String]] {
        let calendar = Calendar.current
        var titles: [Date: [String]] = [:]
        for day in snapshot.days where calendar.isDate(day.date, equalTo: month, toGranularity: .month) {
            guard !day.items.isEmpty else { continue }
            titles[calendar.startOfDay(for: day.date)] = hidesContent
                ? day.items.map { _ in "비공개 일정" }
                : day.items.map(\.title)
        }
        return titles
    }
}

enum WallpaperCalendarStyle: String, CaseIterable, Identifiable {
    case label
    case strip

    var id: String { rawValue }
    var title: String {
        switch self {
        case .label: "레이블형"
        case .strip: "일정 스트립형"
        }
    }
}

enum WallpaperBackdropStyle: String, CaseIterable, Identifiable {
    case aurora
    case graphite
    case dusk

    var id: String { rawValue }
    var title: String {
        switch self {
        case .aurora: "오로라"
        case .graphite: "그래파이트"
        case .dusk: "노을"
        }
    }
}

enum WallpaperGlassStrength: String, CaseIterable, Identifiable {
    case clear
    case balanced
    case focused

    var id: String { rawValue }
    var title: String {
        switch self {
        case .clear: "맑게"
        case .balanced: "균형"
        case .focused: "집중"
        }
    }
    var tintOpacity: Double {
        switch self {
        case .clear: 0.10
        case .balanced: 0.20
        case .focused: 0.34
        }
    }
}

private struct WallpaperBackdrop: View {
    let style: WallpaperBackdropStyle

    var body: some View {
        ZStack {
            LinearGradient(
                colors: style.baseColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(style.topGlow.opacity(0.8))
                .frame(width: 330, height: 330)
                .blur(radius: 48)
                .offset(x: 120, y: -250)
            Circle()
                .fill(style.bottomGlow.opacity(0.62))
                .frame(width: 360, height: 360)
                .blur(radius: 56)
                .offset(x: -150, y: 250)
            Color.black.opacity(0.08)
        }
        .ignoresSafeArea()
    }
}

private extension WallpaperBackdropStyle {
    var baseColors: [Color] {
        switch self {
        case .aurora: [Color(red: 0.04, green: 0.06, blue: 0.15), Color(red: 0.08, green: 0.22, blue: 0.30)]
        case .graphite: [Color(red: 0.04, green: 0.04, blue: 0.05), Color(red: 0.22, green: 0.24, blue: 0.28)]
        case .dusk: [Color(red: 0.10, green: 0.08, blue: 0.22), Color(red: 0.36, green: 0.16, blue: 0.24)]
        }
    }
    var topGlow: Color {
        switch self {
        case .aurora: Color(red: 0.38, green: 0.28, blue: 0.82)
        case .graphite: Color.white.opacity(0.26)
        case .dusk: Color(red: 0.76, green: 0.28, blue: 0.48)
        }
    }
    var bottomGlow: Color {
        switch self {
        case .aurora: Color(red: 0.05, green: 0.65, blue: 0.70)
        case .graphite: Color(red: 0.30, green: 0.34, blue: 0.42)
        case .dusk: Color(red: 0.96, green: 0.48, blue: 0.25)
        }
    }
}

private struct WallpaperClock: View {
    let date: Date

    var body: some View {
        VStack(spacing: -4) {
            Text(dateTitle)
                .font(.subheadline.weight(.semibold))
            Text("9:41")
                .font(.system(size: 76, weight: .thin, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.92))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("잠금화면 시스템 시계 미리보기")
    }

    private var dateTitle: String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let weekday = ["일", "월", "화", "수", "목", "금", "토"][calendar.component(.weekday, from: date) - 1]
        return "\(month)월 \(day)일 \(weekday)요일"
    }
}

private struct WallpaperCalendarPanel: View {
    let month: Date
    let titlesByDay: [Date: [String]]
    let calendarStyle: WallpaperCalendarStyle
    let glassStrength: WallpaperGlassStrength
    let isExport: Bool
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdays = ["월", "화", "수", "목", "금", "토", "일"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle)
                    .font(.headline)
                Spacer()
                Text("\(monthScheduleCount)개 일정")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                }
                ForEach(monthDates.indices, id: \.self) { index in
                    if let day = monthDates[index] {
                        WallpaperCalendarDay(
                            date: day,
                            titles: titlesByDay[day] ?? [],
                            isToday: calendar.isDateInToday(day),
                            style: calendarStyle
                        )
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }
        }
        .padding(16)
        .foregroundStyle(.white)
        .wallpaperGlassSurface(tintOpacity: glassStrength.tintOpacity, isExport: isExport)
    }

    private var monthTitle: String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        return "\(parts.year ?? 0)년 \(parts.month ?? 0)월"
    }

    private var monthDates: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month)
        else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) + 5) % 7
        return Array(repeating: nil, count: leading)
            + days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map(Optional.some)
    }

    private var monthScheduleCount: Int {
        titlesByDay.values.reduce(0) { $0 + $1.count }
    }
}

private struct WallpaperCalendarDay: View {
    let date: Date
    let titles: [String]
    let isToday: Bool
    let style: WallpaperCalendarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.caption.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? .black : .white.opacity(0.9))
                    .frame(width: 24, height: 24)
                    .background(isToday ? .white : .clear, in: Circle())
                if titles.count > 1 {
                    Text("+\(titles.count - 1)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            if let first = titles.first {
                switch style {
                case .label:
                    HStack(spacing: 3) {
                        Capsule()
                            .fill(.white.opacity(0.72))
                            .frame(width: 2, height: 12)
                        Text(first)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(.white.opacity(0.82))
                case .strip:
                    Text(first)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                        .background(
                            .white.opacity(isToday ? 0.22 : 0.12),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Calendar.current.component(.day, from: date))일, 일정 \(titles.count)개")
    }
}

private struct WallpaperSystemActions: View {
    var body: some View {
        HStack {
            systemButton("flashlight.off.fill")
            Spacer()
            systemButton("camera.fill")
        }
        .padding(.horizontal, 28)
        .accessibilityHidden(true)
    }

    private func systemButton(_ image: String) -> some View {
        Image(systemName: image)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.32), in: Circle())
    }
}

private extension View {
    @ViewBuilder
    func wallpaperGlassSurface(tintOpacity: Double, isExport: Bool) -> some View {
        if isExport {
            // ImageRenderer can't rasterize materials or glass effects, so
            // exports use a flat translucent fill over the backdrop instead.
            background(
                .black.opacity(0.24 + tintOpacity),
                in: RoundedRectangle(cornerRadius: MemdoMetrics.widgetRadius, style: .continuous)
            )
            .overlay { wallpaperGlassStroke }
        } else if #available(iOS 26.0, *) {
            glassEffect(
                .regular.tint(.black.opacity(tintOpacity)),
                in: .rect(cornerRadius: MemdoMetrics.widgetRadius)
            )
            .overlay { wallpaperGlassStroke }
        } else {
            background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: MemdoMetrics.widgetRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MemdoMetrics.widgetRadius, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.75)
            }
        }
    }

    var wallpaperGlassStroke: some View {
        RoundedRectangle(cornerRadius: MemdoMetrics.widgetRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.24), .white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
    }
}
