import SFTransitWatchPackage
import Foundation
import WidgetKit

/// Writes a next-arrival snapshot to the shared App Group so the
/// complication timeline provider can read it without a network call.
///
/// The complication has two slots — morning and afternoon — each pinned to a
/// stop ID chosen in Settings. When the watch app refreshes arrivals for a
/// stop that is in one of those slots, we write the snapshot to that slot's
/// keys. A refresh for a stop that isn't in either slot is a no-op, so
/// opening a random nearby stop doesn't clobber your commute data.
enum ComplicationUpdater {
    private static let suiteName = CommuteSlotsManager.appGroupSuiteName
    private static let defaults = UserDefaults(suiteName: suiteName) ?? .standard

    /// Update the slot that owns `stopId`, if any. No-op otherwise.
    @MainActor
    static func update(
        stopId: String,
        stopName: String,
        route: String,
        arrivalTime: Date,
        slotsManager: CommuteSlotsManager
    ) {
        guard let slot = slotsManager.slot(for: stopId) else { return }
        write(slot: slot, stopName: stopName, route: route, arrivalTime: arrivalTime)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Direct writer — separated so tests (and the widget-target code, once
    /// it grows) can inspect per-slot keys without going through a slots
    /// manager.
    static func write(slot: CommuteSlotsManager.Slot, stopName: String, route: String, arrivalTime: Date) {
        defaults.set(stopName, forKey: StorageKey.stopName(slot))
        defaults.set(route, forKey: StorageKey.route(slot))
        defaults.set(arrivalTime, forKey: StorageKey.arrivalTime(slot))
    }

    enum StorageKey {
        static func stopName(_ slot: CommuteSlotsManager.Slot) -> String {
            "complication_\(slot.rawValue)_stop_name"
        }
        static func route(_ slot: CommuteSlotsManager.Slot) -> String {
            "complication_\(slot.rawValue)_route"
        }
        static func arrivalTime(_ slot: CommuteSlotsManager.Slot) -> String {
            "complication_\(slot.rawValue)_arrival_time"
        }

        // Nearby favorites keys
        static let nearbyStopName = "complication_nearby_stop_name"
        static let nearbyRoute = "complication_nearby_route"
        static let nearbyArrivalTime = "complication_nearby_arrival_time"
    }

    @MainActor
    static func updateNearby(
        stopName: String,
        route: String,
        arrivalTime: Date
    ) {
        defaults.set(stopName, forKey: StorageKey.nearbyStopName)
        defaults.set(route, forKey: StorageKey.nearbyRoute)
        defaults.set(arrivalTime, forKey: StorageKey.nearbyArrivalTime)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
