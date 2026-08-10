import AppIntents
import CoreLocation
import SwiftUI

// MARK: - Agency Choice

public enum TransitAgencyChoice: String, AppEnum, CaseIterable, Sendable {
    case muni = "SF"
    case bart = "BA"
    case acTransit = "AC"
    case caltrain = "CT"
    case goldenGate = "GG"
    case samTrans = "SM"
    case vta = "SC"

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transit Agency"
    public static let caseDisplayRepresentations: [TransitAgencyChoice: DisplayRepresentation] = [
        .muni: "Muni",
        .bart: "BART",
        .acTransit: "AC Transit",
        .caltrain: "Caltrain",
        .goldenGate: "Golden Gate",
        .samTrans: "SamTrans",
        .vta: "VTA"
    ]

    public var displayName: String {
        switch self {
        case .muni: return "Muni"
        case .bart: return "BART"
        case .acTransit: return "AC Transit"
        case .caltrain: return "Caltrain"
        case .goldenGate: return "Golden Gate"
        case .samTrans: return "SamTrans"
        case .vta: return "VTA"
        }
    }
}

// MARK: - Shared Helpers

func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

/// `stops` must be non-empty — callers only invoke this after confirming there's at least
/// one favorite. Pure and separate from `perform()` so it's directly unit-testable.
func nearestFavorite(among stops: [BusStop], location: CLLocation) -> BusStop {
    stops.min { $0.distance(to: location) < $1.distance(to: location) }!
}

// MARK: - Check Nearby Stops Intent

public struct CheckNearbyStopsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Nearby Stops"
    public static let description = IntentDescription("Shows transit stops near your current location.")
    public static let openAppWhenRun = true

    @Parameter(title: "Agency")
    public var agency: TransitAgencyChoice?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        persistSelectedAgency(agency)
        return .result()
    }
}

@MainActor
func persistSelectedAgency(_ agency: TransitAgencyChoice?) {
    UserDefaults.standard.set(agency?.rawValue ?? "", forKey: Agency.selectedAgencyKey)
}

// MARK: - Check Stop Arrivals Intent

public struct CheckStopArrivalsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Check Bus Times"
    public static let description = IntentDescription("Shows upcoming arrivals for a stop.")
    public static let openAppWhenRun = true

    @Parameter(title: "Stop Name")
    public var stopName: String?

    @Parameter(title: "Agency")
    public var agency: TransitAgencyChoice?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        persistSelectedAgency(agency)
        let text = Self.dialogText(agency: agency, stopName: stopName)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }

    @MainActor
    static func dialogText(agency: TransitAgencyChoice?, stopName: String?) -> String {
        // A worker-provisioned user has no 511 key but is fully configured, so gate on the
        // same predicate the rest of the app uses rather than the raw API key.
        guard ConfigurationManager.shared.isConfigured else {
            return "Please configure your 511.org API key in SF Transit Watch settings."
        }
        let prefix = agency.map { "\($0.displayName) " } ?? ""
        if let name = stopName {
            return "Opening \(prefix)arrivals for \(name) in SF Transit Watch."
        }
        return "Opening SF Transit Watch to show nearby \(prefix)arrivals."
    }
}

// MARK: - Check Favorite Arrival Intent

public struct CheckFavoriteArrivalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Next Bus for My Favorite Stop"
    public static let description = IntentDescription("Speaks the next arrivals at your nearest favorited stop.")
    public static let openAppWhenRun = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ConfigurationManager.shared.isConfigured else {
            return .result(dialog: IntentDialog(stringLiteral: "Please configure your 511.org API key in SF Transit Watch settings."))
        }

        let favorites = FavoritesManager.allFavorites()
        guard !favorites.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "You don't have any favorite stops yet. Add one in SF Transit Watch."))
        }

        let stop: BusStop
        if favorites.count == 1 {
            stop = favorites[0]
        } else {
            guard let location = await LocationManager().currentLocationOnce(timeout: 8) else {
                return .result(dialog: IntentDialog(stringLiteral: "Enable location access for SF Transit Watch to use this."))
            }
            stop = nearestFavorite(among: favorites, location: location)
        }

        let api = TransitAPI()
        guard let arrivals = await withTimeout(seconds: 8, operation: { await api.fetchArrivals(for: stop.id, agency: stop.agency) }) else {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't reach 511 right now, try again shortly."))
        }
        // `fetchArrivals` never throws — it returns [] on every failure path (bad key, 429
        // backoff, transport error) and records the failure on `errorMessage` instead. An
        // empty array is only a genuine "no arrivals" case when `errorMessage` is nil.
        guard api.errorMessage == nil else {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't reach 511 right now, try again shortly."))
        }

        return .result(dialog: IntentDialog(stringLiteral: Self.arrivalsDialogText(stopName: stop.name, arrivals: arrivals)))
    }

    static func arrivalsDialogText(stopName: String, arrivals: [BusArrival]) -> String {
        let sorted = arrivals.sorted { $0.arrivalTime < $1.arrivalTime }
        guard let first = sorted.first else {
            return "No upcoming arrivals for \(stopName) right now."
        }
        if sorted.count == 1 {
            return "The \(first.route) arrives at \(stopName) in \(first.minutesAway) minutes."
        }
        let second = sorted[1]
        if second.route == first.route {
            return "The \(first.route) arrives at \(stopName) in \(first.minutesAway) minutes, then \(second.minutesAway) minutes."
        }
        return "The \(first.route) arrives at \(stopName) in \(first.minutesAway) minutes, then the \(second.route) in \(second.minutesAway) minutes."
    }
}

// MARK: - Check Route Arrivals Intent

enum StopResolution {
    case single(BusStop)
    case needsLocation
    case ambiguous([BusStop])
}

/// Pure decision logic for which favorited stop to use, kept separate from `perform()`
/// so it's unit-testable without a live AppIntents/Siri context (see Task 3's design note).
/// `candidates` must be non-empty — callers only invoke this after confirming at least one
/// favorite serves the requested route.
func resolveStop(from candidates: [BusStop], location: CLLocation?, disambiguationThreshold: CLLocationDistance = 50) -> StopResolution {
    guard candidates.count > 1 else {
        return .single(candidates[0])
    }
    guard let location else {
        return .needsLocation
    }
    let sorted = candidates.sorted { $0.distance(to: location) < $1.distance(to: location) }
    // Compare the two nearest stops' distance *from each other*, not the delta of their
    // distances from `location` — two stops on opposite sides of an intersection can be
    // near-equidistant from the user while sitting far apart from each other, and two stops
    // can be genuinely close together while one is much nearer to the user than the other.
    if sorted[0].distance(to: sorted[1].location) <= disambiguationThreshold {
        return .ambiguous(sorted)
    }
    return .single(sorted[0])
}

/// Starts one route lookup per favorite in parallel and waits up to `timeout` seconds for
/// every lookup to report in, returning the favorites that serve `routeNumber` (in their
/// original order) — or `nil` if the deadline passes first.
///
/// Deliberately *not* built on `withTimeout`/`withTaskGroup`. A task group's timeout race
/// has to call `group.cancelAll()` to let the group's scope close, and that cancels the
/// still-in-flight lookups too. That's actively harmful here: `TransitAPI.fetchRoutes`
/// swallows a cancelled `URLSession` request as `[]` and then writes that `[]` into
/// `StopRoutesCache` with a 7-day TTL, so one slow-network Siri invocation could leave a
/// stop cached as "serves no routes" for a week. Instead the lookups are unstructured
/// `Task`s (which never inherit cancellation from their spawning context and which nothing
/// here ever cancels) reporting through an `AsyncStream`, and the deadline is just another
/// element in that same stream. Hitting the deadline abandons the *wait* — the lookups keep
/// running to completion in the background and cache whatever the real answer turns out to
/// be. The only task this cancels is its own sleeping timer.
@MainActor
func favoritesServingRoute(
    among favorites: [BusStop],
    routeNumber: String,
    timeout: TimeInterval,
    fetchRoutes: @escaping @Sendable @MainActor (BusStop) async -> [String]
) async -> [BusStop]? {
    enum Report: Sendable {
        case lookup(index: Int, match: BusStop?)
        case deadline
    }

    guard !favorites.isEmpty else { return [] }

    let (stream, continuation) = AsyncStream<Report>.makeStream()
    for (index, favorite) in favorites.enumerated() {
        Task { @MainActor in
            let routes = await fetchRoutes(favorite)
            let matches = routes.contains { $0.caseInsensitiveCompare(routeNumber) == .orderedSame }
            continuation.yield(.lookup(index: index, match: matches ? favorite : nil))
        }
    }
    let timer = Task {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        continuation.yield(.deadline)
    }
    defer { timer.cancel() }

    var matches: [(index: Int, stop: BusStop)] = []
    var reported = 0
    for await report in stream {
        switch report {
        case .deadline:
            return nil
        case .lookup(let index, let match):
            if let match {
                matches.append((index, match))
            }
            reported += 1
            if reported == favorites.count {
                return matches.sorted { $0.index < $1.index }.map(\.stop)
            }
        }
    }
    return nil
}

enum DirectionResolution {
    case resolved(String)
    case noMatch(available: [String])
    case needsDisambiguation([String])
}

/// Pure decision logic for which direction group to speak. `groups` must be non-empty —
/// callers only invoke this after confirming at least one arrival exists for the route.
func resolveDirection(requested: String?, groups: [String: [BusArrival]]) -> DirectionResolution {
    if let requested {
        if let matchKey = groups.keys.first(where: {
            $0.localizedCaseInsensitiveContains(requested) || requested.localizedCaseInsensitiveContains($0)
        }) {
            return .resolved(matchKey)
        }
        return .noMatch(available: groups.keys.sorted())
    }
    if groups.count > 1 {
        return .needsDisambiguation(groups.keys.sorted())
    }
    return .resolved(groups.keys.first!)
}

public struct CheckRouteArrivalsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Next Bus for a Route"
    public static let description = IntentDescription("Finds your nearest favorited stop on a route and speaks its next arrivals.")
    public static let openAppWhenRun = false

    @Parameter(title: "Route Number")
    public var routeNumber: String

    @Parameter(title: "Direction")
    public var direction: String?

    @Parameter(title: "Stop Choice")
    public var stopChoice: String?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ConfigurationManager.shared.isConfigured else {
            return .result(dialog: IntentDialog(stringLiteral: "Please configure your 511.org API key in SF Transit Watch settings."))
        }

        let favorites = FavoritesManager.allFavorites()
        guard !favorites.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "You don't have any favorite stops yet. Add one in SF Transit Watch."))
        }

        let api = TransitAPI()
        // fetchRoutes results are cached per stop/agency (TransitAPI.stopRoutesCache), but a
        // cold cache still means one /StopTimetable round trip per favorite here — known
        // limitation. Run them in parallel with a shared 8s deadline (matching the location and
        // arrivals fetches below) so a large favorites list can't stall past every other
        // timeout-guarded step in this intent. Hitting that deadline abandons the wait but
        // deliberately leaves the lookups running — see `favoritesServingRoute`.
        guard let matching = await favoritesServingRoute(
            among: favorites,
            routeNumber: routeNumber,
            timeout: 8,
            fetchRoutes: { await api.fetchRoutes(for: $0.id, agency: $0.agency) }
        ) else {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't reach 511 right now, try again shortly."))
        }
        guard !matching.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "None of your favorite stops serve route \(routeNumber)."))
        }

        let location = matching.count > 1 ? await LocationManager().currentLocationOnce(timeout: 8) : nil
        let stop: BusStop
        switch resolveStop(from: matching, location: location) {
        case .single(let resolved):
            stop = resolved
        case .needsLocation:
            return .result(dialog: IntentDialog(stringLiteral: "Enable location access for SF Transit Watch to use this."))
        case .ambiguous(let candidates):
            let chosenName = try await $stopChoice.requestDisambiguation(
                among: candidates.map { $0.name },
                dialog: IntentDialog(stringLiteral: "Which stop?")
            )
            stop = candidates.first { $0.name == chosenName } ?? candidates[0]
        }

        guard let allArrivals = await withTimeout(seconds: 8, operation: { await api.fetchArrivals(for: stop.id, agency: stop.agency) }) else {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't reach 511 right now, try again shortly."))
        }
        // `fetchArrivals` never throws — it returns [] on every failure path (bad key, 429
        // backoff, transport error) and records the failure on `errorMessage` instead. An
        // empty/route-filtered-empty result is only a genuine "no arrivals" case when
        // `errorMessage` is nil.
        guard api.errorMessage == nil else {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't reach 511 right now, try again shortly."))
        }
        let routeArrivals = allArrivals.filter { $0.route.caseInsensitiveCompare(routeNumber) == .orderedSame }
        guard !routeArrivals.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "No upcoming arrivals for \(stop.name) right now."))
        }

        var groups: [String: [BusArrival]] = [:]
        for arrival in routeArrivals {
            groups[arrival.destination, default: []].append(arrival)
        }

        let resolvedDirection: String
        switch resolveDirection(requested: direction, groups: groups) {
        case .resolved(let key):
            resolvedDirection = key
        case .noMatch(let available):
            let directionText = direction ?? ""
            return .result(dialog: IntentDialog(stringLiteral: "\(stop.name) doesn't have a \(directionText) \(routeNumber). Available: \(available.joined(separator: " or "))."))
        case .needsDisambiguation(let options):
            resolvedDirection = try await $direction.requestDisambiguation(
                among: options,
                dialog: IntentDialog(stringLiteral: "Which direction?")
            )
        }

        return .result(dialog: IntentDialog(stringLiteral: Self.arrivalsDialogText(
            routeNumber: routeNumber,
            stopName: stop.name,
            arrivals: groups[resolvedDirection] ?? []
        )))
    }

    static func arrivalsDialogText(routeNumber: String, stopName: String, arrivals: [BusArrival]) -> String {
        let sorted = arrivals.sorted { $0.arrivalTime < $1.arrivalTime }
        guard let first = sorted.first else {
            return "No upcoming arrivals for \(stopName) right now."
        }
        if sorted.count == 1 {
            return "The \(routeNumber) at \(stopName) arrives in \(first.minutesAway) minutes."
        }
        let second = sorted[1]
        return "The \(routeNumber) at \(stopName) arrives in \(first.minutesAway) minutes, then \(second.minutesAway) minutes."
    }
}
