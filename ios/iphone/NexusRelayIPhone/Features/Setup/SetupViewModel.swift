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
    
    @Published var photosStatus: PhotoLibraryAuthorizationStatus = .notDetermined
    @Published var destinationFolderName = "iPhone Uploads"
    
    var checklistRows: [SetupChecklistRow] {
        SetupChecklistRow.makeRows(
            serverURL: serverURL,
            username: username,
            photosStatus: photosStatus,
            destinationFolderName: destinationFolderName
        )
    }
    
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
        self.destinationFolderName = s.destinationFolderName
        self.photosStatus = photosScanner.authorizationStatus()
    }

    func saveAndLogin() async {
        guard BackendURLValidator.isValid(serverURL), let url = URL(string: serverURL) else {
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

            let grantedStatus = await ensurePhotosAuthorization()
            self.photosStatus = grantedStatus
            guard grantedStatus == .authorized || grantedStatus == .limited else {
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
