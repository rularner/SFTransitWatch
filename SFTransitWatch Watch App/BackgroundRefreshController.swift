import Foundation
import WatchKit
import UserNotifications
import WidgetKit
import CoreLocation
import SFTransitWatchPackage

/// Drives periodic background work for the watch app:
/// - keeps the complication's per-slot snapshot fresh while the app is asleep
/// - fires a local notification when the active commute bus is within the user's
///   configurable alert window and travel-time lead
@MainActor
final class BackgroundRefreshController {
    static let shared = BackgroundRefreshController()

    static let refreshInterval: TimeInterval = 15 * 60

    private static let notificationDedupGap: TimeInterval = 5 * 60
    private static func lastNotifiedKey(for slot: CommuteSlotsManager.Slot) -> String {
        "last_notified_arrival_\(slot.rawValue)"
    }

    private let defaults = UserDefaults.standard
    private let locationManager = CLLocationManager()

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

        let pinnedStop = pinnedStop(for: stopId)
        let storedAgencies = UserDefaults(suiteName: SharedAgenciesManager.appGroupSuiteName)?
            .string(forKey: EnabledAgencies.storageKey) ?? ""
        let agency = pinnedStop?.agency ?? EnabledAgencies.defaultAgency(storedAgencies)

        let api = TransitAPI()
        let arrivals = await api.fetchArrivals(for: stopId, agency: agency)
        guard let first = arrivals.first else { return }

        let stopName = pinnedStop?.name ?? "Stop \(stopId)"
        ComplicationUpdater.write(
            slot: slot,
            stopName: stopName,
            route: first.route,
            arrivalTime: first.arrivalTime
        )
        WidgetCenter.shared.reloadAllTimelines()

        // Fresh instance always reads latest UserDefaults — same pattern as CommuteSlotsManager above.
        let alertSettings = AlertSettingsManager()
        guard let candidate = alertSettings.qualifyingArrival(from: arrivals, for: slot) else { return }

        // Location check: if the user is already at the stop, suppress for the rest of today.
        if let stop = pinnedStop, stop.hasValidLocation,
           locationManager.authorizationStatus == .authorizedWhenInUse
            || locationManager.authorizationStatus == .authorizedAlways {
            if let location = try? await LocationProvider.requestLocation(),
               stop.distance(to: location) <= AlertSettingsManager.atStopRadiusMeters {
                alertSettings.suppressAtStop(for: slot)
                return
            }
        }

        await fireImminentNotificationIfNeeded(
            for: candidate,
            slot: slot,
            stopName: stopName,
            travelMinutes: alertSettings.travelMinutes(for: slot)
        )
    }

    /// Requests notification authorization. Also prompts for location "when in use"
    /// on first call so at-stop detection can work during future background refreshes.
    func requestNotificationAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            if granted, locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
            return granted
        } catch {
            return false
        }
    }

    private func fireImminentNotificationIfNeeded(
        for arrival: BusArrival,
        slot: CommuteSlotsManager.Slot,
        stopName: String,
        travelMinutes: Int
    ) async {
        let key = Self.lastNotifiedKey(for: slot)
        let lastNotified = defaults.object(forKey: key) as? Date ?? .distantPast
        guard arrival.arrivalTime.timeIntervalSince(lastNotified) > Self.notificationDedupGap else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(arrival.route) approaching"
        if travelMinutes > 0 {
            content.body = "\(arrival.minutesAway) min to \(stopName) — leave now"
        } else {
            content.body = arrival.minutesAway == 0
                ? "Due now at \(stopName)"
                : "\(arrival.minutesAway) min away at \(stopName)"
        }
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

    private func pinnedStop(for stopId: String) -> BusStop? {
        guard let data = UserDefaults.standard.data(forKey: "PinnedStops"),
              let pinned = try? JSONDecoder().decode([BusStop].self, from: data) else {
            return nil
        }
        return pinned.first(where: { $0.id == stopId })
    }
}
