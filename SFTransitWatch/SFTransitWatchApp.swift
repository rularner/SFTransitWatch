import SwiftUI

@main
struct SFTransitWatchApp: App {
    init() {
        PhoneSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
