import SwiftUI

enum NRDesign {
    enum ColorToken {
        static let appBackground = Color(red: 0.980, green: 0.980, blue: 0.973)
        static let surface = Color.white
        static let surfaceMuted = Color(red: 0.955, green: 0.960, blue: 0.955)
        static let surfaceElevated = Color(red: 1.000, green: 1.000, blue: 0.995)
        static let primaryText = Color(red: 0.090, green: 0.090, blue: 0.090)
        static let secondaryText = Color(red: 0.420, green: 0.447, blue: 0.502)
        static let hairline = Color(red: 0.902, green: 0.906, blue: 0.890)
        static let divider = hairline
        static let accent = Color(red: 0.039, green: 0.518, blue: 0.647)
        static let accentSoft = accent.opacity(0.12)
        static let success = Color(red: 0.180, green: 0.678, blue: 0.420)
        static let successSoft = success.opacity(0.12)
        static let warning = Color(red: 0.949, green: 0.722, blue: 0.294)
        static let warningSoft = warning.opacity(0.14)
        static let error = Color(red: 0.847, green: 0.290, blue: 0.290)
        static let errorSoft = error.opacity(0.12)
        static let overlayScrim = Color.black.opacity(0.42)
    }

    enum Radius {
        static let thumbnail: CGFloat = 8
        static let row: CGFloat = 10
        static let capsule: CGFloat = 24
    }

    enum Spacing {
        static let page: CGFloat = 16
        static let row: CGFloat = 10
        static let section: CGFloat = 20
    }

    enum IconSize {
        static let status: CGFloat = 19
        static let row: CGFloat = 21
        static let action: CGFloat = 18
    }
}

extension View {
    func nrPageBackground() -> some View {
        background(NRDesign.ColorToken.appBackground.ignoresSafeArea())
    }

    func nrCard() -> some View {
        padding(14)
            .background(
                NRDesign.ColorToken.surface,
                in: RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                    .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
            )
    }
}
