import SwiftUI

@main
struct SFTransitWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PhoneSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Telemetry.shared.flush()
            }
        }
    }
}
