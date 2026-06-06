import SwiftUI

enum NRDesign {
    enum ColorToken {
        static let appBackground = Color(red: 0.980, green: 0.980, blue: 0.973)
        static let surface = Color.white
        static let primaryText = Color(red: 0.090, green: 0.090, blue: 0.090)
        static let secondaryText = Color(red: 0.420, green: 0.447, blue: 0.502)
        static let hairline = Color(red: 0.902, green: 0.906, blue: 0.890)
        static let accent = Color(red: 0.039, green: 0.518, blue: 0.647)
        static let success = Color(red: 0.180, green: 0.678, blue: 0.420)
        static let warning = Color(red: 0.949, green: 0.722, blue: 0.294)
        static let error = Color(red: 0.847, green: 0.290, blue: 0.290)
    }

    enum Radius {
        static let thumbnail: CGFloat = 8
        static let row: CGFloat = 12
        static let capsule: CGFloat = 24
    }

    enum Spacing {
        static let page: CGFloat = 20
        static let row: CGFloat = 12
        static let section: CGFloat = 24
    }
}

extension View {
    func nrPageBackground() -> some View {
        background(NRDesign.ColorToken.appBackground.ignoresSafeArea())
    }
}
