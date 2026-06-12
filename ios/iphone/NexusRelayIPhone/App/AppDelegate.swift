import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.nexusrelay.iphone.sync", using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.runBackgroundSync(task: processingTask)
        }
        return true
    }

    private func runBackgroundSync(task: BGProcessingTask) {
        BackgroundSyncScheduler.shared.scheduleNextSyncAttempt()
        
        let work = Task {
            do {
                let orchestrator = try self.resolveSyncOrchestrator()
                _ = try await orchestrator.startSync()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private func resolveSyncOrchestrator() throws -> SyncOrchestrator {
        let settingsStore = UserDefaultsSettingsStore()
        let settings = settingsStore.settings
        guard let url = settings.backendBaseURL else {
            throw SyncError.missingFolder
        }
        
        let sessionStore = CookieSessionStore(keychain: SystemKeychainStore())
        let runtime = AuthSessionRuntime(baseURL: url, sessionStore: sessionStore)
        let apiClient = runtime.apiClient
        
        let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ledger.sqlite")
        var isCorrupt = false
        let ledger = LedgerFactory.createOrRecoverLedger(dbURL: dbURL, isCorrupted: &isCorrupt)
        
        let scanner = PhotoKitPhotoLibraryClient()
        let exporter = PhotoKitAssetExporter()
        let tempStore = SystemTemporaryFileStore()
        let engine = SystemUploadEngine(apiClient: apiClient)
        
        return SystemSyncOrchestrator(
            apiClient: apiClient,
            photosScanner: scanner,
            ledger: ledger,
            exporter: exporter,
            tempFileStore: tempStore,
            uploadEngine: engine,
            settingsStore: settingsStore
        )
    }
}
