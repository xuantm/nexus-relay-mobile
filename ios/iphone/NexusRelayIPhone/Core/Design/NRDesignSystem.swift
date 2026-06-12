import SwiftUI
import UIKit

enum NRDesign {
    enum ColorToken {
        static let appBackground = Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0)
                : UIColor(red: 0.980, green: 0.980, blue: 0.973, alpha: 1.0)
        })

        static let surface = Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1.0)
                : UIColor.white
        })

        static let surfaceMuted = Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1.0)
                : UIColor(red: 0.955, green: 0.960, blue: 0.955, alpha: 1.0)
        })

        static let surfaceElevated = Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 1.0)
                : UIColor(red: 1.000, green: 1.000, blue: 0.995, alpha: 1.0)
        })

        static let primaryText = Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
                : UIColor(red: 0.090, green: 0.090, blue: 0.090, alpha: 1.0)
        })

        static let secondaryText = Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.65, green: 0.67, blue: 0.72, alpha: 1.0)
                : UIColor(red: 0.420, green: 0.447, blue: 0.502, alpha: 1.0)
        })

        static let hairline = Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0)
                : UIColor(red: 0.902, green: 0.906, blue: 0.890, alpha: 1.0)
        })

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
