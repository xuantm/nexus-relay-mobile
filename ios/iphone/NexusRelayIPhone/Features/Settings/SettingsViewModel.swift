import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var username = "Not signed in"
    @Published var serverURLString = ""
    @Published var folderName = ""
    @Published var wifiOnly = true
    @Published var includeVideos = true
    @Published var includeLivePhotoVideo = false
    @Published var photosAccessText = "Unknown"

    private let settingsStore: SettingsStore
    private let photosScanner: PhotoLibraryClient
    private let sessionStore: SessionStore

    init(
        settingsStore: SettingsStore = UserDefaultsSettingsStore(),
        photosScanner: PhotoLibraryClient = PhotoKitPhotoLibraryClient(),
        sessionStore: SessionStore = CookieSessionStore()
    ) {
        self.settingsStore = settingsStore
        self.photosScanner = photosScanner
        self.sessionStore = sessionStore
        load()
    }

    func load() {
        let settings = settingsStore.settings
        username = sessionStore.currentSession?.username ?? "Not signed in"
        serverURLString = settings.backendBaseURL?.absoluteString ?? "Not set"
        folderName = settings.destinationFolderName
        wifiOnly = settings.wifiOnly
        includeVideos = settings.includeVideos
        includeLivePhotoVideo = settings.includeLivePhotoVideo
        photosAccessText = photosText(photosScanner.authorizationStatus())
    }

    func saveSyncPreferences() {
        var settings = settingsStore.settings
        settings.wifiOnly = wifiOnly
        settings.includeVideos = includeVideos
        settings.includeLivePhotoVideo = includeLivePhotoVideo
        settingsStore.settings = settings
    }

    private func photosText(_ status: PhotoLibraryAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Full access"
        case .limited: return "Limited access"
        case .denied: return "Access denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested"
        }
    }
}
