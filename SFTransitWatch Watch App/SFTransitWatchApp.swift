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
                    if let key = apiKey(from: url), !key.isEmpty {
                        storedAPIKey = key
                    }
                }
        }
    }

    // Accepts either:
    //   sftransitwatch://key/YOUR_API_KEY                          (custom scheme)
    //   https://rularner.github.io/sftransitwatch/key?k=YOUR_KEY   (universal link)
    private func apiKey(from url: URL) -> String? {
        if url.scheme == "sftransitwatch", url.host == "key" {
            return String(url.path.dropFirst())
        }
        if url.scheme == "https",
           url.host == "rularner.github.io",
           url.path == "/sftransitwatch/key",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            return components.queryItems?.first { $0.name == "k" }?.value
        }
        return nil
    }
} 