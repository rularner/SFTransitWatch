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
                "Show nearby train stops in \(.applicationName)",
                "Show nearby muni stops in \(.applicationName)",
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
                "Check train times in \(.applicationName)",
                "Check muni times in \(.applicationName)",
                "Check \(\.$agency) times in \(.applicationName)",
                "Show arrivals in \(.applicationName)",
                "Show \(\.$agency) arrivals in \(.applicationName)",
                "When is the next bus in \(.applicationName)",
                "When is the next train in \(.applicationName)",
                "When is the next muni in \(.applicationName)",
                "When is the next \(\.$agency) in \(.applicationName)"
            ],
            shortTitle: "Bus Times",
            systemImageName: "bus.fill"
        )
        AppShortcut(
            intent: CheckFavoriteArrivalIntent(),
            phrases: [
                "What's my next bus in \(.applicationName)",
                "What's my next train in \(.applicationName)",
                "What's my next muni in \(.applicationName)",
                "When's my bus in \(.applicationName)",
                "When's my train in \(.applicationName)",
                "When's my muni in \(.applicationName)",
                "Next arrival for my favorite stop in \(.applicationName)"
            ],
            shortTitle: "My Next Bus",
            systemImageName: "star.fill"
        )
        AppShortcut(
            intent: CheckRouteArrivalsIntent(),
            phrases: [
                "Check route arrivals in \(.applicationName)",
                "When is the next bus on my route in \(.applicationName)",
                "When is the next train on my route in \(.applicationName)",
                "When is the next muni on my route in \(.applicationName)"
            ],
            shortTitle: "Route Arrivals",
            systemImageName: "arrow.triangle.turn.up.right.circle.fill"
        )
    }
}
