import Foundation
@testable import SFTransitWatch_Watch_App

/// Hand-curated SF-realistic data for App Store snapshot tests.
/// Editing these values changes what appears in the screenshots.
enum WatchSnapshotFixtures {

    static func nearbyStops() -> [BusStop] {
        let stops: [(name: String, code: String, routes: [String], lat: Double, lon: Double)] = [
            ("Castro Station",          "16992", ["K", "L", "M", "T"],   37.7626, -122.4350),
            ("Market St & Castro St",   "15184", ["F", "24", "33", "35"], 37.7619, -122.4351),
            ("Church St & Duboce Ave",  "13338", ["J", "N"],              37.7697, -122.4290),
            ("18th St & Castro St",     "14225", ["33", "35"],            37.7610, -122.4351),
            ("Van Ness & Market",       "16996", ["9", "47", "49", "F"],  37.7752, -122.4194),
        ]
        return stops.map { tuple in
            BusStop(
                id: "SF:\(tuple.code)",
                name: tuple.name,
                code: tuple.code,
                latitude: tuple.lat,
                longitude: tuple.lon,
                routes: tuple.routes,
                agency: "SF"
            )
        }
    }

    /// First nearby stop is also pinned (so it shows in BOTH "Pinned" and "Nearby" sections —
    /// matches the production behavior where pinned stops aren't filtered out of nearby results).
    static func pinnedStops() -> [BusStop] {
        Array(nearbyStops().prefix(1))
    }

    /// Mark the second nearby stop as a favorite (shows the star icon in the row).
    static func favoriteStopIDs() -> Set<String> {
        Set(nearbyStops().dropFirst().prefix(1).map { $0.id })
    }

    /// The single stop used for the BusArrivalView snapshot.
    static func sampleStop() -> BusStop {
        nearbyStops()[0]  // Castro Station
    }

    /// Plausible Muni Metro arrivals at Castro Station.
    /// All times measured from a fixed reference date so the rendered "min" labels are deterministic.
    static func arrivals(for stop: BusStop) -> [BusArrival] {
        let now = referenceNow
        return [
            BusArrival(route: "K", destination: "Ingleside",  arrivalTime: now.addingTimeInterval(2 * 60),  isRealTime: true,  now: now),
            BusArrival(route: "L", destination: "Taraval",    arrivalTime: now.addingTimeInterval(7 * 60),  isRealTime: true,  now: now),
            BusArrival(route: "M", destination: "Ocean View", arrivalTime: now.addingTimeInterval(14 * 60), isRealTime: true,  now: now),
            BusArrival(route: "T", destination: "Third",      arrivalTime: now.addingTimeInterval(22 * 60), isRealTime: false, now: now),
        ]
    }

    /// Fixed point in time so `BusArrival.minutesAway` (which is computed from `arrivalTime - now`)
    /// produces stable values when fixtures are constructed at any wall-clock time.
    /// Value: 2026-01-01 09:00:00 UTC. Any fixed date works; this one is just memorable.
    static let referenceNow: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 1
        components.hour = 9; components.minute = 0; components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()
}
