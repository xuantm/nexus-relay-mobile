import Foundation
import SwiftUI

@MainActor
final class SetupViewModel: ObservableObject {
    @Published var serverURL = ""
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
            isSignedIn: sessionStore.currentSession != nil,
            userEmail: sessionStore.currentSession?.email ?? sessionStore.currentSession?.username,
            photosStatus: photosStatus,
            destinationFolderName: destinationFolderName
        )
    }
    
    private let settingsStore: SettingsStore
    private let photosScanner: PhotoLibraryClient
    private let sessionStore: SessionStore
    private let authCoordinator: GoogleAuthCoordinating
    
    init(
        settingsStore: SettingsStore = UserDefaultsSettingsStore(),
        photosScanner: PhotoLibraryClient = PhotoKitPhotoLibraryClient(),
        sessionStore: SessionStore = CookieSessionStore(),
        authCoordinator: GoogleAuthCoordinating = GoogleAuthCoordinator()
    ) {
        self.settingsStore = settingsStore
        self.photosScanner = photosScanner
        self.sessionStore = sessionStore
        self.authCoordinator = authCoordinator
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
            
            let authResult = try await authCoordinator.signIn(baseURL: url)
            
            let code: String
            switch authResult {
            case .success(let callbackCode):
                code = callbackCode
            case .pending:
                errorMessage = "Access request sent. An admin must approve this Google account before uploads can start."
                isLoading = false
                return
            case .denied(let reason):
                errorMessage = "Google sign-in was denied: \(reason ?? "No reason provided")"
                isLoading = false
                return
            case .invalid:
                errorMessage = "Invalid redirect received from sign-in."
                isLoading = false
                return
            }
            
            let keychain = SystemKeychainStore()
            let csrfProvider = SystemCSRFTokenProvider()
            let httpClient = SystemHTTPClient(baseURL: url, sessionStore: sessionStore, csrfProvider: csrfProvider)
            let apiClient = SystemNexusRelayAPIClient(baseURL: url, httpClient: httpClient, sessionStore: sessionStore)
            
            _ = try await apiClient.exchangeIosSession(code: code)
            
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
