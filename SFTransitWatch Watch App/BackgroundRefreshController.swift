import Foundation
import WatchKit
import UserNotifications
import WidgetKit

/// Drives periodic background work for the watch app:
/// - keeps the complication's per-slot snapshot fresh while the app is asleep
/// - fires a local notification when the active commute bus is ≤2 minutes away
///
/// Background refresh on watchOS is throttled — schedule the next one each
/// time we're woken, and trust the system to budget us appropriately.
@MainActor
final class BackgroundRefreshController {
    static let shared = BackgroundRefreshController()

    /// How far out to ask the system to wake us. The OS treats this as a
    /// hint; effective interval is usually 15+ minutes.
    static let refreshInterval: TimeInterval = 15 * 60

    /// Threshold for "your bus is here" alerting.
    static let imminentMinutes = 2

    /// Minimum gap between two notifications for the same slot, to guard
    /// against firing on consecutive refreshes if the user is right at the
    /// stop while the bus dwells.
    private static let notificationDedupGap: TimeInterval = 5 * 60

    private static let notificationsEnabledKey = "notifications_imminent_arrivals_enabled"
    private static func lastNotifiedKey(for slot: CommuteSlotsManager.Slot) -> String {
        "last_notified_arrival_\(slot.rawValue)"
    }

    private let defaults = UserDefaults.standard

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Self.notificationsEnabledKey) }
        set { defaults.set(newValue, forKey: Self.notificationsEnabledKey) }
    }

    /// Called on app launch and after each background wake. Always
    /// reschedules — if the user has no slots configured, the work is a
    /// no-op but we keep the timer alive for when they do configure one.
    func scheduleNextRefresh() {
        let target = Date().addingTimeInterval(Self.refreshInterval)
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: target,
            userInfo: nil
        ) { error in
            if let error {
                NSLog("scheduleBackgroundRefresh failed: \(error.localizedDescription)")
            }
        }
    }

    /// Called from `WKApplicationDelegate` when the system hands us a
    /// background refresh window. Performs the slot fetch, writes the
    /// snapshot, optionally fires a local notification, schedules the next
    /// wake, and signals completion.
    func handleBackgroundRefresh(_ task: WKApplicationRefreshBackgroundTask) async {
        defer {
            scheduleNextRefresh()
            task.setTaskCompletedWithSnapshot(false)
        }

        let slotsManager = CommuteSlotsManager()
        guard let slot = slotsManager.activeSlotWithFallback(),
              let stopId = slotsManager.stopId(for: slot),
              !stopId.isEmpty else {
            return
        }

        let api = TransitAPI()
        let arrivals = await api.fetchArrivals(for: stopId)
        guard let first = arrivals.first else { return }

        let stopName = pinnedStopName(for: stopId) ?? "Stop \(stopId)"
        ComplicationUpdater.write(
            slot: slot,
            stopName: stopName,
            route: first.route,
            minutesAway: first.minutesAway
        )
        WidgetCenter.shared.reloadAllTimelines()

        if notificationsEnabled, first.minutesAway <= Self.imminentMinutes {
            await fireImminentNotificationIfNeeded(for: first, slot: slot, stopName: stopName)
        }
    }

    /// Asks for notification authorization. Safe to call repeatedly; the
    /// system only prompts the first time.
    func requestNotificationAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    private func fireImminentNotificationIfNeeded(
        for arrival: BusArrival,
        slot: CommuteSlotsManager.Slot,
        stopName: String
    ) async {
        let key = Self.lastNotifiedKey(for: slot)
        let lastNotified = defaults.object(forKey: key) as? Date ?? .distantPast
        guard arrival.arrivalTime.timeIntervalSince(lastNotified) > Self.notificationDedupGap else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(arrival.route) approaching"
        content.body = arrival.minutesAway == 0
            ? "Due now at \(stopName)"
            : "\(arrival.minutesAway) min away at \(stopName)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "imminent_\(slot.rawValue)_\(Int(arrival.arrivalTime.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            defaults.set(arrival.arrivalTime, forKey: key)
        } catch {
            NSLog("imminent notification add failed: \(error.localizedDescription)")
        }
    }

    /// Best-effort lookup of the human-readable stop name from the user's
    /// pinned list. Falls back to the stop ID if not found.
    private func pinnedStopName(for stopId: String) -> String? {
        guard let data = UserDefaults.standard.data(forKey: "PinnedStops"),
              let pinned = try? JSONDecoder().decode([BusStop].self, from: data) else {
            return nil
        }
        return pinned.first(where: { $0.id == stopId })?.name
    }
}
