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
        minutesAway: Int,
        slotsManager: CommuteSlotsManager
    ) {
        guard let slot = slotsManager.slot(for: stopId) else { return }
        write(slot: slot, stopName: stopName, route: route, minutesAway: minutesAway)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Direct writer — separated so tests (and the widget-target code, once
    /// it grows) can inspect per-slot keys without going through a slots
    /// manager.
    static func write(slot: CommuteSlotsManager.Slot, stopName: String, route: String, minutesAway: Int) {
        defaults.set(stopName, forKey: StorageKey.stopName(slot))
        defaults.set(route, forKey: StorageKey.route(slot))
        defaults.set(minutesAway, forKey: StorageKey.minutesAway(slot))
    }

    enum StorageKey {
        static func stopName(_ slot: CommuteSlotsManager.Slot) -> String {
            "complication_\(slot.rawValue)_stop_name"
        }
        static func route(_ slot: CommuteSlotsManager.Slot) -> String {
            "complication_\(slot.rawValue)_route"
        }
        static func minutesAway(_ slot: CommuteSlotsManager.Slot) -> String {
            "complication_\(slot.rawValue)_minutes_away"
        }
    }
}
