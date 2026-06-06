import Foundation
import BackgroundTasks

final class BackgroundSyncScheduler {
    static let shared = BackgroundSyncScheduler()
    private let taskId = "com.nexusrelay.iphone.sync"

    func registerBackgroundTasks(orchestrator: SyncOrchestrator) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handleBackgroundSync(task: processingTask, orchestrator: orchestrator)
        }
    }

    func scheduleNextSyncAttempt() {
        let request = BGProcessingTaskRequest(identifier: taskId)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    private func handleBackgroundSync(task: BGProcessingTask, orchestrator: SyncOrchestrator) {
        scheduleNextSyncAttempt()

        let work = Task {
            do {
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
}
