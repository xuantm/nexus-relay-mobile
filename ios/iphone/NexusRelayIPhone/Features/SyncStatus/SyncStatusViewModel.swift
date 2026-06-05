import Foundation
import SwiftUI

enum ActiveSyncStatus: String {
    case idle = "Idle"
    case scanning = "Scanning"
    case exporting = "Exporting"
    case uploading = "Uploading"
    case error = "Error"
}

@MainActor
final class SyncStatusViewModel: ObservableObject {
    @Published var queuedCount = 0
    @Published var uploadedCount = 0
    @Published var failedCount = 0
    @Published var exportingCount = 0
    @Published var uploadingCount = 0
    
    @Published var serverURLString = ""
    @Published var folderName = ""
    @Published var activeStatus: ActiveSyncStatus = .idle
    @Published var lastSyncDate: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var isLoggedOut = false
    
    private let settingsStore: SettingsStore
    private var orchestrator: SyncOrchestrator?
    private var reconciliationService: ReconciliationService?
    private var ledger: UploadLedger?
    
    init(settingsStore: SettingsStore = UserDefaultsSettingsStore()) {
        self.settingsStore = settingsStore
        initializeServices()
    }
    
    func initializeServices() {
        let settings = settingsStore.settings
        guard let url = settings.backendBaseURL else { return }
        self.serverURLString = url.absoluteString
        self.folderName = settings.destinationFolderName
        
        let keychain = SystemKeychainStore()
        let sessionStore = CookieSessionStore(keychain: keychain)
        let csrfProvider = SystemCSRFTokenProvider()
        let httpClient = SystemHTTPClient(baseURL: url, sessionStore: sessionStore, csrfProvider: csrfProvider)
        let apiClient = SystemNexusRelayAPIClient(baseURL: url, httpClient: httpClient, sessionStore: sessionStore)
        
        let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ledger.sqlite")
        var isCorrupt = false
        let ledger = LedgerFactory.createOrRecoverLedger(dbURL: dbURL, isCorrupted: &isCorrupt)
        self.ledger = ledger
        
        let scanner = PhotoKitPhotoLibraryClient()
        let exporter = PhotoKitAssetExporter()
        let tempStore = SystemTemporaryFileStore()
        let engine = SystemUploadEngine(apiClient: apiClient)
        
        self.orchestrator = SystemSyncOrchestrator(
            apiClient: apiClient,
            photosScanner: scanner,
            ledger: ledger,
            exporter: exporter,
            tempFileStore: tempStore,
            uploadEngine: engine,
            settingsStore: settingsStore
        )
        
        self.reconciliationService = ReconciliationService(
            apiClient: apiClient,
            photosScanner: scanner,
            ledger: ledger
        )
        
        Task {
            await refreshCounts()
        }
    }
    
    func refreshCounts() async {
        guard let ledger = ledger else { return }
        do {
            let counts = try await ledger.getLedgerCounts()
            self.queuedCount = counts.queued
            self.uploadedCount = counts.uploaded
            self.failedCount = counts.failed
            self.exportingCount = counts.exporting
            self.uploadingCount = counts.uploading
            
            // Adjust active status dynamically if syncing
            if activeStatus != .idle && activeStatus != .error {
                if counts.uploading > 0 {
                    activeStatus = .uploading
                } else if counts.exporting > 0 {
                    activeStatus = .exporting
                }
            }
        } catch {
            print("Failed to get ledger counts: \(error)")
        }
    }
    
    func syncNow() async {
        guard let orchestrator = orchestrator else {
            errorMessage = "Sync orchestrator not initialized"
            activeStatus = .error
            return
        }
        
        errorMessage = nil
        activeStatus = .scanning
        
        let pollingTask = Task {
            while activeStatus != .idle && activeStatus != .error && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshCounts()
            }
        }
        
        do {
            _ = try await orchestrator.startSync()
            lastSyncDate = Date()
            activeStatus = .idle
        } catch {
            errorMessage = error.localizedDescription
            activeStatus = .error
        }
        
        pollingTask.cancel()
        await refreshCounts()
    }
    
    func reconcile() async {
        guard let reconciliationService = reconciliationService,
              let folderId = settingsStore.settings.destinationFolderId else {
            errorMessage = "Reconciliation service not initialized or folder not set"
            activeStatus = .error
            return
        }
        
        errorMessage = nil
        activeStatus = .scanning
        
        do {
            try await reconciliationService.reconcile(folderId: folderId)
            lastSyncDate = Date()
            activeStatus = .idle
        } catch {
            errorMessage = error.localizedDescription
            activeStatus = .error
        }
        
        await refreshCounts()
    }
    
    func logout() {
        let keychain = SystemKeychainStore()
        let sessionStore = CookieSessionStore(keychain: keychain)
        try? sessionStore.clearSession()
        
        let cookieStorage = HTTPCookieStorage.shared
        if let url = settingsStore.settings.backendBaseURL,
           let cookies = cookieStorage.cookies(for: url) {
            for cookie in cookies {
                cookieStorage.deleteCookie(cookie)
            }
        }
        
        settingsStore.settings = .defaults
        
        // Explicitly clear references to trigger deinit / database close before file removal
        self.orchestrator = nil
        self.reconciliationService = nil
        self.ledger = nil
        
        let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ledger.sqlite")
        try? FileManager.default.removeItem(at: dbURL)
        
        self.serverURLString = ""
        self.folderName = ""
        self.queuedCount = 0
        self.uploadedCount = 0
        self.failedCount = 0
        self.exportingCount = 0
        self.uploadingCount = 0
        self.activeStatus = .idle
        self.lastSyncDate = nil
        self.errorMessage = nil
        
        self.isLoggedOut = true
    }
}
