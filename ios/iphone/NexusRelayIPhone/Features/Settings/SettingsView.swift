import SwiftUI

struct SettingsView: View {
    var onLogout: () -> Void

    var body: some View {
        NavigationStack {
            Button("Sign out") {
                onLogout()
            }
            .navigationTitle("Settings")
        }
    }
}
