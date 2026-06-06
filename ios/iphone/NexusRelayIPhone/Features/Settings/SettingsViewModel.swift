import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var serverURLString = ""
    @Published var folderName = ""
    @Published var wifiOnly = true
    @Published var includeVideos = true
    @Published var includeLivePhotoVideo = false
    @Published var photosAccessText = "Unknown"

    private let settingsStore: SettingsStore
    private let photosScanner: PhotoLibraryClient

    init(
        settingsStore: SettingsStore = UserDefaultsSettingsStore(),
        photosScanner: PhotoLibraryClient = PhotoKitPhotoLibraryClient()
    ) {
        self.settingsStore = settingsStore
        self.photosScanner = photosScanner
        load()
    }

    func load() {
        let settings = settingsStore.settings
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
