import BackgroundTasks
import Foundation

/// Periodic background sync via BGTaskScheduler. iOS wakes the app every few
/// hours (at its discretion, influenced by usage patterns and battery) so
/// drives push to the server without the app being opened. This is additive —
/// sync still runs after every drive and on foreground.
enum BackgroundSync {
    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let taskIdentifier = "com.miles.sync"

    /// Call before the app finishes launching (AppDelegate).
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier, using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Call whenever the app goes to the background. Re-submitting replaces
    /// any pending request, so this is safe to call repeatedly.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected in Simulator and when Background App Refresh is off.
            NSLog("Miles: background sync scheduling failed: \(error)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Always chain the next wake before doing the work.
        schedule()

        let work = Task { @MainActor in
            await SyncEngine.shared.sync()
        }
        task.expirationHandler = {
            work.cancel()
        }
        Task {
            _ = await work.result
            task.setTaskCompleted(success: true)
        }
    }
}
