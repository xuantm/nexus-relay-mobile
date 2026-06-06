import SwiftUI

struct SyncStatusView: View {
    var onLogout: () -> Void

    var body: some View {
        AppShellView(onLogout: onLogout)
    }
}
