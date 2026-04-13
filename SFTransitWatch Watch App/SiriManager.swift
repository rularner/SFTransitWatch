import AppIntents
import SwiftUI
import WatchKit

// MARK: - Check Nearby Stops Intent

struct CheckNearbyStopsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Nearby Stops"
    static let description = IntentDescription("Shows transit stops near your current location.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Check Stop Arrivals Intent

struct CheckStopArrivalsIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Bus Times"
    static let description = IntentDescription("Shows upcoming arrivals for a stop.")
    static let openAppWhenRun = true

    @Parameter(title: "Stop Name")
    var stopName: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let api = TransitAPI()
        let key = UserDefaults.standard.string(forKey: "511_API_KEY") ?? ""
        guard !key.isEmpty else {
            return .result(dialog: "Please configure your 511.org API key in SF Transit Watch settings.")
        }

        if let name = stopName {
            return .result(dialog: "Opening arrivals for \(name) in SF Transit Watch.")
        }
        return .result(dialog: "Opening SF Transit Watch to show nearby arrivals.")
    }
}

// MARK: - App Shortcuts Provider

struct SFTransitAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckNearbyStopsIntent(),
            phrases: [
                "Find nearby stops in \(.applicationName)",
                "Show nearby bus stops in \(.applicationName)",
                "Nearby transit in \(.applicationName)"
            ],
            shortTitle: "Nearby Stops",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: CheckStopArrivalsIntent(),
            phrases: [
                "Check bus times in \(.applicationName)",
                "Show arrivals in \(.applicationName)",
                "When is the next bus in \(.applicationName)"
            ],
            shortTitle: "Bus Times",
            systemImageName: "bus.fill"
        )
    }
}
