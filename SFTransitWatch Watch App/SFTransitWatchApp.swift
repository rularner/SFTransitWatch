import SwiftUI
import WatchKit

@main
struct SFTransitWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("511_API_KEY") private var storedAPIKey = ""
    @AppStorage("WORKER_TOKEN") private var storedWorkerToken = ""
    @AppStorage("WORKER_BASE_URL") private var storedWorkerBaseURL = ""
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if let key = WorkerConfigLink.apiKey(from: url), !key.isEmpty {
                        storedAPIKey = key
                        return
                    }
                    if let config = WorkerConfigLink.workerConfig(from: url) {
                        storedWorkerBaseURL = config.url
                        storedWorkerToken = config.token
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Telemetry.shared.flush()
            }
        }
    }
} 