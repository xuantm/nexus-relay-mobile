import Foundation
import SwiftUI

@MainActor
final class SetupViewModel: ObservableObject {
    @Published var serverURL = ""
    @Published var username = ""
    @Published var password = ""
    @Published var wifiOnly = true
    @Published var includeVideos = true
    @Published var includeLivePhotos = false
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSetupComplete = false
    
    private let settingsStore: SettingsStore
    private let photosScanner: PhotoLibraryClient
    
    init(
        settingsStore: SettingsStore = UserDefaultsSettingsStore(),
        photosScanner: PhotoLibraryClient = PhotoKitPhotoLibraryClient()
    ) {
        self.settingsStore = settingsStore
        self.photosScanner = photosScanner
        let s = settingsStore.settings
        self.serverURL = s.backendBaseURL?.absoluteString ?? ""
        self.wifiOnly = s.wifiOnly
        self.includeVideos = s.includeVideos
        self.includeLivePhotos = s.includeLivePhotoVideo
    }

    func saveAndLogin() async {
        guard let url = URL(string: serverURL), url.scheme == "http" || url.scheme == "https" else {
            errorMessage = "Invalid Server URL (must start with http/https)"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            var s = settingsStore.settings
            s.backendBaseURL = url
            s.wifiOnly = wifiOnly
            s.includeVideos = includeVideos
            s.includeLivePhotoVideo = includeLivePhotos
            settingsStore.settings = s
            
            let keychain = SystemKeychainStore()
            let sessionStore = CookieSessionStore(keychain: keychain)
            let csrfProvider = SystemCSRFTokenProvider()
            let httpClient = SystemHTTPClient(baseURL: url, sessionStore: sessionStore, csrfProvider: csrfProvider)
            let apiClient = SystemNexusRelayAPIClient(baseURL: url, httpClient: httpClient, sessionStore: sessionStore)
            
            _ = try await apiClient.login(username: username, password: password)
            
            let folders = try await apiClient.listRootFolders()
            let defaultName = s.destinationFolderName
            let folderId: UUID
            
            if let existing = folders.first(where: { $0.name.lowercased() == defaultName.lowercased() }) {
                folderId = existing.id
            } else {
                let newFolder = try await apiClient.createFolder(name: defaultName, parentId: nil)
                folderId = newFolder.id
            }
            
            s.destinationFolderId = folderId
            settingsStore.settings = s

            let photosStatus = await ensurePhotosAuthorization()
            guard photosStatus == .authorized || photosStatus == .limited else {
                throw SyncError.photosPermissionRequired
            }
            
            isSetupComplete = true
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }

    private func ensurePhotosAuthorization() async -> PhotoLibraryAuthorizationStatus {
        let currentStatus = photosScanner.authorizationStatus()
        if currentStatus == .notDetermined {
            return await photosScanner.requestAuthorization()
        }

        return currentStatus
    }
}
