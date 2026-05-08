import SwiftUI
import WatchKit

@main
struct SFTransitWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("511_API_KEY") private var storedAPIKey = ""
    @AppStorage("WORKER_TOKEN") private var storedWorkerToken = ""
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if let key = apiKey(from: url), !key.isEmpty {
                        storedAPIKey = key
                        return
                    }
                    if let token = workerToken(from: url), !token.isEmpty {
                        storedWorkerToken = token
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Telemetry.shared.flush()
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

    // Accepts either:
    //   sftransitwatch://wt/YOUR_TOKEN                              (custom scheme)
    //   https://rularner.github.io/sftransitwatch/wt?t=YOUR_TOKEN   (universal link)
    private func workerToken(from url: URL) -> String? {
        if url.scheme == "sftransitwatch", url.host == "wt" {
            return String(url.path.dropFirst())
        }
        if url.scheme == "https",
           url.host == "rularner.github.io",
           url.path == "/sftransitwatch/wt",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            return components.queryItems?.first { $0.name == "t" }?.value
        }
        return nil
    }
} 