import AppIntents
import SFTransitWatchPackage

// MARK: - App Shortcuts Provider

struct SFTransitAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckNearbyStopsIntent(),
            phrases: [
                "Find nearby stops in \(.applicationName)",
                "Find nearby \(\.$agency) stops in \(.applicationName)",
                "Show nearby bus stops in \(.applicationName)",
                "Show nearby \(\.$agency) in \(.applicationName)",
                "Nearby transit in \(.applicationName)",
                "Nearby \(\.$agency) in \(.applicationName)"
            ],
            shortTitle: "Nearby Stops",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: CheckStopArrivalsIntent(),
            phrases: [
                "Check bus times in \(.applicationName)",
                "Check \(\.$agency) times in \(.applicationName)",
                "Show arrivals in \(.applicationName)",
                "Show \(\.$agency) arrivals in \(.applicationName)",
                "When is the next bus in \(.applicationName)",
                "When is the next \(\.$agency) in \(.applicationName)"
            ],
            shortTitle: "Bus Times",
            systemImageName: "bus.fill"
        )
    }
}

// MARK: - Siri Intent Donation Manager

final class SiriManager {
    static func shouldDonateNearbyStops(stops: [BusStop]) -> Bool {
        return !stops.isEmpty
    }

    static func createNearbyStopsIntent(for stops: [BusStop]) -> CheckNearbyStopsIntent? {
        guard !stops.isEmpty else { return nil }
        return CheckNearbyStopsIntent()
    }

    func donateNearbyStops(_ stops: [BusStop]) {
        if SnapshotMode.isActive { return }
        guard Self.shouldDonateNearbyStops(stops: stops) else { return }
        if let intent = Self.createNearbyStopsIntent(for: stops) {
            _ = intent
        }
    }
}
