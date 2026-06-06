import SwiftUI

struct AppShellView: View {
    var onLogout: () -> Void

    var body: some View {
        TabView {
            LibrarySyncView()
                .tabItem {
                    Label("Sync", systemImage: "icloud.and.arrow.up")
                }

            UploadQueueView()
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }

            SettingsView(onLogout: onLogout)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(NRDesign.ColorToken.accent)
    }
}
