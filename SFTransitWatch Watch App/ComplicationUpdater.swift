import Foundation
import WidgetKit

/// Writes the next-arrival snapshot to the shared App Group so the
/// complication timeline provider can read it without a network call.
struct ComplicationUpdater {
    private static let suiteName = "group.org.larner.SFTransitWatch"
    private static let defaults = UserDefaults(suiteName: suiteName) ?? .standard

    static func update(stopName: String, route: String, minutesAway: Int) {
        defaults.set(stopName, forKey: "complication_stop_name")
        defaults.set(route, forKey: "complication_route")
        defaults.set(minutesAway, forKey: "complication_minutes_away")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
