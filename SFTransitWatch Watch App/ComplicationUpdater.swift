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
        updateSlot(slot, stopName: stopName, route: route, arrivalTime: arrivalTime)
    }

    /// Writes the slot's snapshot and reloads widget timelines only when the
    /// route or arrival time actually changed. The arrivals screen polls
    /// every 30s, and calling `reloadAllTimelines()` unconditionally on every
    /// poll burns through WidgetKit's reload budget — see
    /// `ComplicationSnapshot.hasChanged`.
    static func updateSlot(_ slot: CommuteSlotsManager.Slot, stopName: String, route: String, arrivalTime: Date) {
        let changed = ComplicationSnapshot.hasChanged(
            existingRoute: defaults.string(forKey: StorageKey.route(slot)),
            existingArrivalTime: defaults.object(forKey: StorageKey.arrivalTime(slot)) as? Date,
            newRoute: route,
            newArrivalTime: arrivalTime
        )
        write(slot: slot, stopName: stopName, route: route, arrivalTime: arrivalTime)
        guard changed else { return }
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
        static let nearbyStopId = "complication_nearby_stop_id"
        static let nearbyStopName = "complication_nearby_stop_name"
        static let nearbyRoute = "complication_nearby_route"
        static let nearbyArrivalTime = "complication_nearby_arrival_time"
    }

    @MainActor
    static func updateNearby(
        stopId: String,
        stopName: String,
        route: String,
        arrivalTime: Date
    ) {
        let changed = ComplicationSnapshot.hasChanged(
            existingRoute: defaults.string(forKey: StorageKey.nearbyRoute),
            existingArrivalTime: defaults.object(forKey: StorageKey.nearbyArrivalTime) as? Date,
            newRoute: route,
            newArrivalTime: arrivalTime
        )
        defaults.set(stopId, forKey: StorageKey.nearbyStopId)
        defaults.set(stopName, forKey: StorageKey.nearbyStopName)
        defaults.set(route, forKey: StorageKey.nearbyRoute)
        defaults.set(arrivalTime, forKey: StorageKey.nearbyArrivalTime)
        guard changed else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
