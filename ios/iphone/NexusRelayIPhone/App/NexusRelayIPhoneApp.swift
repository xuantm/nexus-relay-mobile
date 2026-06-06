import SwiftUI

@main
struct NexusRelayIPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isSetupComplete: Bool = {
        let store = UserDefaultsSettingsStore()
        let settings = store.settings
        let photosStatus = PhotoKitPhotoLibraryClient().authorizationStatus()
        let hasPhotosAccess = photosStatus == .authorized || photosStatus == .limited
        return settings.backendBaseURL != nil && settings.destinationFolderId != nil && hasPhotosAccess
    }()

    var body: some Scene {
        WindowGroup {
            if isSetupComplete {
                AppShellView(onLogout: {
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
