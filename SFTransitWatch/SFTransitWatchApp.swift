import SwiftUI
import SFTransitWatchPackage

@main
struct SFTransitWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PhoneSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if let key = WorkerConfigLink.apiKey(from: url), !key.isEmpty {
                        ConfigurationManager.shared.apiKey = key
                        return
                    }
                    if let config = WorkerConfigLink.workerConfig(from: url) {
                        ConfigurationManager.shared.setWorkerConfig(url: config.url, token: config.token)
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
