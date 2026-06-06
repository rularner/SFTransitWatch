import AppIntents
import SFTransitWatchPackage

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
