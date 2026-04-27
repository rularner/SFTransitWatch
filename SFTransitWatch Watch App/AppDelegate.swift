import WatchKit

/// Receives the background-task callbacks SwiftUI doesn't surface on its
/// own. Each task gets dispatched to `BackgroundRefreshController` if it's
/// our scheduled refresh, otherwise marked complete so the system reclaims
/// it promptly.
final class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            BackgroundRefreshController.shared.scheduleNextRefresh()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    await BackgroundRefreshController.shared.handleBackgroundRefresh(refreshTask)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
