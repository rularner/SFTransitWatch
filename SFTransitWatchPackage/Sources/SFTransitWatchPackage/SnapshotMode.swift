import Foundation
import CoreLocation

/// Test-only data fixtures and activation flag for App Store snapshot tests.
///
/// `SnapshotMode.isActive` is true only when the launch argument `-SNAPSHOT_MODE` is
/// passed to the watch app's process. Production launches never include this flag, so
/// the snapshot-mode branches in `TransitAPI`, `LocationManager`, `FavoritesManager`,
/// and `PinnedStopsManager` are inert in shipped builds.
public enum SnapshotMode {

    public static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-SNAPSHOT_MODE")
    }

    /// When true, the app should start directly on `BusArrivalView` for
    /// `sampleStop` instead of the stop list. Used by snapshot tests that
    /// need the arrival or compass screen without navigating from the list.
    public static var showArrivalDirectly: Bool {
        isActive && (
            ProcessInfo.processInfo.arguments.contains("-SNAPSHOT_ARRIVAL") ||
            ProcessInfo.processInfo.arguments.contains("-SNAPSHOT_LOCATION")
        )
    }

    /// When true, `BusArrivalView` should open on the location/compass tab (tab 1)
    /// rather than the arrivals tab (tab 0). Requires `showArrivalDirectly` to also
    /// be true so the app starts on BusArrivalView.
    public static var showLocationTab: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-SNAPSHOT_LOCATION")
    }

    /// 5 hand-curated SF Muni Metro stops centered around the Castro neighborhood.
    /// Editing these values changes what appears in the App Store screenshots.
    public static let nearbyStops: [BusStop] = [
        BusStop(id: "SF:16992", name: "Castro Station",          code: "16992", latitude: 37.7626, longitude: -122.4350, routes: ["K", "L", "M", "T"],      agency: "SF"),
        BusStop(id: "SF:15184", name: "Market St & Castro St",   code: "15184", latitude: 37.7619, longitude: -122.4351, routes: ["F", "24", "33", "35"],   agency: "SF"),
        BusStop(id: "SF:13338", name: "Church St & Duboce Ave",  code: "13338", latitude: 37.7697, longitude: -122.4290, routes: ["J", "N"],                agency: "SF"),
        BusStop(id: "SF:14225", name: "18th St & Castro St",     code: "14225", latitude: 37.7610, longitude: -122.4351, routes: ["33", "35"],              agency: "SF"),
        BusStop(id: "SF:16996", name: "Van Ness & Market",       code: "16996", latitude: 37.7752, longitude: -122.4194, routes: ["9", "47", "49", "F"],    agency: "SF"),
    ]

    /// Castro Station is also pinned (renders the "Pinned" section).
    public static let pinnedStops: [BusStop] = Array(nearbyStops.prefix(1))

    /// Market & Castro is favorited (renders the star icon on its row).
    public static let favoriteStopIDs: Set<String> = Set(nearbyStops.dropFirst().prefix(1).map { $0.id })

    /// Castro Station — used for `BusArrivalView`'s screenshot.
    public static let sampleStop: BusStop = nearbyStops[0]

    /// 4 plausible Muni Metro arrivals at Castro Station.
    /// Constructed against a fixed reference time so `BusArrival.minutesAway` is deterministic
    /// regardless of when the snapshot test runs.
    public static func arrivals(for stop: BusStop) -> [BusArrival] {
        let now = referenceNow
        return [
            BusArrival(route: "K", destination: "Ingleside",  arrivalTime: now.addingTimeInterval(2 * 60),  isRealTime: true,  now: now),
            BusArrival(route: "L", destination: "Taraval",    arrivalTime: now.addingTimeInterval(7 * 60),  isRealTime: true,  now: now),
            BusArrival(route: "M", destination: "Ocean View", arrivalTime: now.addingTimeInterval(14 * 60), isRealTime: true,  now: now),
            BusArrival(route: "T", destination: "Third",      arrivalTime: now.addingTimeInterval(22 * 60), isRealTime: false, now: now),
        ]
    }

    /// 2026-01-01 09:00:00 UTC. Any fixed date works; this one is just memorable.
    static let referenceNow: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 1
        components.hour = 9; components.minute = 0; components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    /// Castro Station's coordinates. Used by `LocationManager` when active.
    public static let fixedLocation = CLLocation(latitude: 37.7626, longitude: -122.4350)
}
