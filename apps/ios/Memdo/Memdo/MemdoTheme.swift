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
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(MemdoTheme.ink)
            Spacer()
            Text(trailing)
                .font(.caption.bold())
                .foregroundStyle(MemdoTheme.secondaryInk)
        }
    }
}

extension View {
    func memdoCard(radius: CGFloat = MemdoMetrics.cardRadius) -> some View {
        background(MemdoTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
