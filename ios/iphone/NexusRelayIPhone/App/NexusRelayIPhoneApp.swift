import SwiftUI

@main
struct NexusRelayIPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isSetupComplete: Bool = {
        let store = UserDefaultsSettingsStore()
        let settings = store.settings
        return settings.backendBaseURL != nil && settings.destinationFolderId != nil
    }()

    var body: some Scene {
        WindowGroup {
            if isSetupComplete {
                SyncStatusView(onLogout: {
                    isSetupComplete = false
                })
            } else {
                SetupView(onSetupSuccess: {
                    isSetupComplete = true
                })
            }
        }
    }
}
