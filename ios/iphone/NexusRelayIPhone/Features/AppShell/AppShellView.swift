import SwiftUI

@MainActor
final class SessionActions: ObservableObject {
    private let syncStatusViewModel = SyncStatusViewModel()

    func logout() {
        syncStatusViewModel.logout()
    }
}

struct AppShellView: View {
    var onLogout: () -> Void
    @StateObject private var sessionActions = SessionActions()

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

            SettingsView(onLogout: {
                sessionActions.logout()
                onLogout()
            })
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(NRDesign.ColorToken.accent)
    }
}

