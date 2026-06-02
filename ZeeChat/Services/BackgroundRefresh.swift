import Foundation
import BackgroundTasks

/// BGAppRefreshTask scheduler — wakes ZeeChat ~every 15 minutes to
/// poll inbox so a notification can fire even when the app has been
/// fully suspended (vs only foreground/background-running).
///
/// iOS controls actual frequency (15 min is the floor; usage patterns
/// shape it). Notifications still arrive when the app is running normally
/// — this is the "I've been on lock screen for an hour" safety net.
enum BackgroundRefresh {
    static let taskID = "com.rishizamvar.zeechat.refresh"

    /// Called once at app launch — registers the handler so iOS knows
    /// what to do when our task ID is woken.
    static func register(refresh: @escaping () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID,
                                        using: nil) { task in
            handle(task as! BGAppRefreshTask, refresh: refresh)
        }
    }

    /// Schedule the next refresh window. Call this after every successful
    /// poll (foreground or background) so iOS keeps the cadence.
    static func schedule(after seconds: TimeInterval = 15 * 60) {
        let req = BGAppRefreshTaskRequest(identifier: taskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        try? BGTaskScheduler.shared.submit(req)
    }

    private static func handle(_ task: BGAppRefreshTask,
                               refresh: @escaping () async -> Void) {
        // Always re-schedule first so a crashing refresh doesn't strand us.
        schedule()
        let work = Task {
            await refresh()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
