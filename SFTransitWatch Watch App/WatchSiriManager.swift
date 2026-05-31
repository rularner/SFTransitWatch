import AppIntents
import SFTransitWatchPackage

struct SFTransitWatchAppShortcuts: AppShortcutsProvider {
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
