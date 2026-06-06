import SwiftUI

struct AppShellView: View {
    var onLogout: () -> Void
    @StateObject private var syncStatusViewModel = SyncStatusViewModel()

    var body: some View {
        TabView {
            LibrarySyncView(
                syncStatusViewModel: syncStatusViewModel,
                onRepairSignIn: {
                    syncStatusViewModel.logout()
                    onLogout()
                }
            )
                .tabItem {
                    Label("Sync", systemImage: "icloud.and.arrow.up")
                }

            UploadQueueView(syncStatusViewModel: syncStatusViewModel)
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }

            SettingsView(onLogout: {
                syncStatusViewModel.logout()
                onLogout()
            })
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(NRDesign.ColorToken.accent)
    }
}
