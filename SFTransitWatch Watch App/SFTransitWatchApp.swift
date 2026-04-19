import SwiftUI
import WatchKit

@main
struct SFTransitWatchApp: App {
    @AppStorage("511_API_KEY") private var storedAPIKey = ""

    init() {
        WatchSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Accept: sftransitwatch://key/YOUR_API_KEY
                    if url.scheme == "sftransitwatch",
                       url.host == "key",
                       !url.path.isEmpty {
                        let key = String(url.path.dropFirst()) // strip leading "/"
                        if !key.isEmpty {
                            storedAPIKey = key
                        }
                    }
                }
        }
    }
} 