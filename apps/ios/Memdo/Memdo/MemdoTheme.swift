import SwiftUI

enum MemdoTheme {
    static let background = Color(red: 0.973, green: 0.972, blue: 0.976)
    static let surface = Color(red: 0.998, green: 0.997, blue: 1.0)
    static let ink = Color(red: 0.141, green: 0.137, blue: 0.169)
    static let secondaryInk = Color(red: 0.40, green: 0.38, blue: 0.44)
    static let outline = Color(red: 0.91, green: 0.89, blue: 0.93)

    static let accent = Color(red: 0.357, green: 0.302, blue: 0.718)
    static let accentSoft = Color(red: 0.925, green: 0.91, blue: 1.0)
    static let mine = Color(red: 0.184, green: 0.447, blue: 0.329)
    static let mineSoft = Color(red: 0.867, green: 0.957, blue: 0.91)
    static let google = Color(red: 0.208, green: 0.392, blue: 0.604)
    static let googleSoft = Color(red: 0.875, green: 0.925, blue: 1.0)
    static let peach = Color(red: 0.64, green: 0.30, blue: 0.16)
    static let peachSoft = Color(red: 1.0, green: 0.886, blue: 0.824)
}

enum MemdoMetrics {
    static let pagePadding: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let fieldRadius: CGFloat = 14
    static let touchTarget: CGFloat = 44
    static let sectionSpacing: CGFloat = 28
}

struct MemdoPageBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.965, green: 0.958, blue: 0.985), location: 0),
                .init(color: MemdoTheme.background, location: 0.42),
                .init(color: MemdoTheme.background, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct MemdoSectionHeader: View {
    let title: String
    let trailing: String?

    init(title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(MemdoTheme.ink)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.bold())
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
        }
    }
}

struct MemdoPageHeader: View {
    let title: String
    let subtitle: String
    let eyebrow: String
    let icon: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MemdoTheme.accent)
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(MemdoTheme.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }

            Spacer(minLength: 8)

            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(MemdoTheme.accent)
                .frame(width: 52, height: 52)
                .background(MemdoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

struct MemdoSection<Content: View>: View {
    let title: String
    let trailing: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MemdoSectionHeader(title: title, trailing: trailing)
            content
        }
    }
}

struct MemdoActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let tintBackground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tintBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MemdoTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MemdoTheme.secondaryInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 68)
            .memdoCard()
        }
        .buttonStyle(.plain)
    }
}

struct MemdoDisclosureRow: View {
    let isExpanded: Bool
    let hiddenCount: Int
    let totalCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(
                    isExpanded ? "일정 접기" : "나머지 \(hiddenCount)개 보기",
                    systemImage: isExpanded ? "chevron.up" : "ellipsis"
                )
                Spacer()
                Text("총 \(totalCount)개")
                    .font(.caption)
                    .foregroundStyle(MemdoTheme.secondaryInk)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MemdoTheme.accent)
            .frame(maxWidth: .infinity, minHeight: MemdoMetrics.touchTarget)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "일정 목록을 세 개로 줄입니다" : "나머지 일정을 이어서 보여줍니다")
    }
}

extension View {
    func memdoCard(radius: CGFloat = MemdoMetrics.cardRadius) -> some View {
        background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func memdoSettingsRow() -> some View {
        frame(minHeight: 52)
            .contentShape(Rectangle())
    }
}
