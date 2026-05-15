import SwiftUI
import SFTransitWatchPackage

@main
struct SFTransitWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var tokenExchange = WorkerTokenExchange()

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
                    if let bootstrap = WorkerConfigLink.workerBootstrap(from: url) {
                        Task {
                            await handleWorkerBootstrap(bootstrap)
                        }
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Telemetry.shared.flush()
            }
        }
    }

    private func handleWorkerBootstrap(_ bootstrap: (url: String, code: String)) async {
        do {
            let token = try await tokenExchange.exchange(code: bootstrap.code, workerURL: bootstrap.url)
            ConfigurationManager.shared.setWorkerConfig(url: bootstrap.url, token: token)
        } catch {
            print("Worker token exchange failed: \(error.localizedDescription)")
        }
    }
}
