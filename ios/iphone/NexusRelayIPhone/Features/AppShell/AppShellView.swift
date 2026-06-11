import SwiftUI

@MainActor
struct AppShellView: View {
    enum AppTab: Hashable {
        case sync
        case queue
        case pixel
        case settings
    }

    var onLogout: () -> Void
    @StateObject private var syncStatusViewModel = SyncStatusViewModel()
    @State private var selectedTab: AppTab = .sync

    var body: some View {
        TabView(selection: $selectedTab) {
            LibrarySyncView(
                syncStatusViewModel: syncStatusViewModel,
                onRepairSignIn: {
                    syncStatusViewModel.logout()
                    onLogout()
                },
                onOpenQueue: {
                    selectedTab = .queue
                }
            )
            .tabItem {
                Label("Sync", systemImage: "arrow.up.circle")
            }
            .tag(AppTab.sync)

            UploadQueueView(syncStatusViewModel: syncStatusViewModel)
                .tabItem {
                    Label("Queue", systemImage: "list.bullet.rectangle")
                }
                .tag(AppTab.queue)

            PixelDeliveryView()
                .tabItem {
                    Label("Pixel", systemImage: "iphone")
                }
                .tag(AppTab.pixel)

            SettingsView(onLogout: {
                syncStatusViewModel.logout()
                onLogout()
            })
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .tint(NRDesign.ColorToken.accent)
        .background(NRDesign.ColorToken.appBackground.ignoresSafeArea())
    }
}
