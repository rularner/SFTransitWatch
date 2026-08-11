import AppIntents
import CoreLocation
import Foundation
import Testing
@testable import SFTransitWatchPackage

// MARK: - IntentDialog text extraction

/// `IntentDialog` has no public accessor for its literal text — it only conforms to
/// `ExpressibleByStringLiteral`/`ExpressibleByStringInterpolation`, not
/// `CustomStringConvertible`. Its single stored property (`storage`) bottoms out in a
/// private Objective-C class (`LNStaticDeferredLocalizedString`) that Swift's `Mirror`
/// cannot see into — that class has no Swift-visible stored properties, so a
/// Mirror-only walk dead-ends and returns nothing. The text is only reachable through
/// that class's own Cocoa `-description`, which is exactly what `String(describing:)`
/// invokes: it renders as
/// `...LocalizedStringResource(key: "<text>", defaultValue: ...)...`. That embeds a
/// live memory address elsewhere in the dump (so comparing the *whole* description is
/// unusable), but the `key: "..."` segment is stable, so we pull just that substring.
///
/// One more wrinkle: `LocalizedStringResource`'s key generation runs the literal
/// through ICU MessageFormat escaping, which backslash-escapes apostrophes (`'` ->
/// `\'`) because a bare `'` is an ICU quoting metacharacter — confirmed empirically
/// against "You don't have any favorite stops..." below. Undo that escaping so the
/// extracted text matches the original source literal exactly.
private func literalText(from dialog: IntentDialog) -> String? {
    let description = String(describing: dialog)
    guard let keyStart = description.range(of: "key: \"")?.upperBound,
          let keyEnd = description.range(of: "\", defaultValue:", range: keyStart..<description.endIndex)?.lowerBound
    else {
        return nil
    }
    return description[keyStart..<keyEnd].replacingOccurrences(of: "\\'", with: "'")
}

/// Records whether a background route lookup ran to completion and whether it saw itself as
/// cancelled. Lock-guarded because it's written from a `Task` the test body outlives.
private final class LookupProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _completed = false
    private var _sawCancellation = false

    var completed: Bool { lock.withLock { _completed } }
    var sawCancellation: Bool { lock.withLock { _sawCancellation } }

    func finish(cancelled: Bool) {
        lock.withLock {
            _completed = true
            _sawCancellation = cancelled
        }
    }
}

// MARK: - Tests

@Suite(.serialized)
struct IntentPerformTests {

    init() {
        UserDefaults.standard.removeObject(forKey: Agency.selectedAgencyKey)
        ConfigurationManager.shared.apiKey = ""
    }

    // MARK: - CheckNearbyStopsIntent

    @Test func agencyNil_writesEmptyString() async throws {
        var intent = CheckNearbyStopsIntent()
        intent.agency = nil
        _ = try await intent.perform()
        #expect(UserDefaults.standard.string(forKey: Agency.selectedAgencyKey) == "")
    }

    @Test func agencySet_writesRawValue() async throws {
        var intent = CheckNearbyStopsIntent()
        intent.agency = .muni
        _ = try await intent.perform()
        #expect(UserDefaults.standard.string(forKey: Agency.selectedAgencyKey) == "SF")
    }

    @Test func nearbyStops_performDoesNotThrow() async throws {
        let intent = CheckNearbyStopsIntent()
        _ = try await intent.perform()
    }

    // MARK: - CheckStopArrivalsIntent

    @Test func noAPIKey_returnsConfigureDialog() async throws {
        // apiKey already cleared in init()
        let text = await CheckStopArrivalsIntent.dialogText(agency: nil, stopName: nil)
        #expect(text == "Please configure your 511.org API key in SF Transit Watch settings.")
    }

    @Test func apiKey_noAgency_noStop_returnsGenericDialog() async throws {
        ConfigurationManager.shared.apiKey = "test-key"
        let text = await CheckStopArrivalsIntent.dialogText(agency: nil, stopName: nil)
        #expect(text == "Opening SF Transit Watch to show nearby arrivals.")
    }

    @Test func apiKey_agencySet_noStop_includesAgencyPrefix() async throws {
        ConfigurationManager.shared.apiKey = "test-key"
        let text = await CheckStopArrivalsIntent.dialogText(agency: .muni, stopName: nil)
        #expect(text == "Opening SF Transit Watch to show nearby Muni arrivals.")
    }

    @Test func apiKey_noAgency_stopSet_includesStopName() async throws {
        ConfigurationManager.shared.apiKey = "test-key"
        let text = await CheckStopArrivalsIntent.dialogText(agency: nil, stopName: "Market & 4th")
        #expect(text == "Opening arrivals for Market & 4th in SF Transit Watch.")
    }

    @Test func apiKey_agencySet_stopSet_includesBoth() async throws {
        ConfigurationManager.shared.apiKey = "test-key"
        let text = await CheckStopArrivalsIntent.dialogText(agency: .bart, stopName: "Civic Center")
        #expect(text == "Opening BART arrivals for Civic Center in SF Transit Watch.")
    }

    @Test func arrivalsIntent_agencySet_writesRawValue() async throws {
        ConfigurationManager.shared.apiKey = "test-key"
        var intent = CheckStopArrivalsIntent()
        intent.agency = .acTransit
        intent.stopName = nil
        _ = try await intent.perform()
        #expect(UserDefaults.standard.string(forKey: Agency.selectedAgencyKey) == "AC")
    }

    // MARK: - withTimeout

    @Test func withTimeout_fastOperation_returnsItsResult() async throws {
        let result = await withTimeout(seconds: 5) { "done" }
        #expect(result == "done")
    }

    @Test func withTimeout_slowOperation_returnsNilAfterTimeout() async throws {
        let start = Date()
        let result = await withTimeout(seconds: 0.2) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return "too late"
        }
        #expect(result == nil)
        #expect(Date().timeIntervalSince(start) < 1)
    }

    // MARK: - CheckFavoriteArrivalIntent

    @Test func nearestFavorite_picksClosestStop() async throws {
        let near = BusStop(id: "near", name: "Near", code: "N", latitude: 37.7001, longitude: -122.4000)
        let far = BusStop(id: "far", name: "Far", code: "F", latitude: 37.8000, longitude: -122.4000)
        let userLocation = CLLocation(latitude: 37.7000, longitude: -122.4000)
        let stop = nearestFavorite(among: [far, near], location: userLocation)
        #expect(stop.id == "near")
    }

    @Test func favoriteArrival_noAPIKey_returnsConfigureDialog() async throws {
        let text = CheckFavoriteArrivalIntent.arrivalsDialogText(stopName: "Market & 4th", arrivals: [])
        // arrivalsDialogText itself doesn't gate on API key (perform() does, before calling it) —
        // this test documents that the empty-arrivals case still produces a sensible dialog.
        #expect(text == "No upcoming arrivals for Market & 4th right now.")
    }

    @Test func favoriteArrival_singleArrival_speaksOne() async throws {
        let now = Date()
        let arrival = BusArrival(route: "22", destination: "Fillmore", arrivalTime: now.addingTimeInterval(240), now: now)
        let text = CheckFavoriteArrivalIntent.arrivalsDialogText(stopName: "Market & 4th", arrivals: [arrival])
        #expect(text == "The 22 arrives at Market & 4th in 4 minutes.")
    }

    @Test func favoriteArrival_twoArrivals_speaksBoth() async throws {
        let now = Date()
        let first = BusArrival(route: "22", destination: "Fillmore", arrivalTime: now.addingTimeInterval(240), now: now)
        let second = BusArrival(route: "22", destination: "Fillmore", arrivalTime: now.addingTimeInterval(1140), now: now)
        let text = CheckFavoriteArrivalIntent.arrivalsDialogText(stopName: "Market & 4th", arrivals: [first, second])
        #expect(text == "The 22 arrives at Market & 4th in 4 minutes, then 19 minutes.")
    }

    @Test func favoriteArrival_unsortedInput_speaksEarliestFirst() async throws {
        let now = Date()
        let later = BusArrival(route: "22", destination: "Fillmore", arrivalTime: now.addingTimeInterval(1140), now: now)
        let sooner = BusArrival(route: "22", destination: "Fillmore", arrivalTime: now.addingTimeInterval(240), now: now)
        let text = CheckFavoriteArrivalIntent.arrivalsDialogText(stopName: "Market & 4th", arrivals: [later, sooner])
        #expect(text == "The 22 arrives at Market & 4th in 4 minutes, then 19 minutes.")
    }

    @Test func favoriteArrival_twoArrivalsSameRoute_keepsShortForm() async throws {
        // A favorited stop's top-two-by-time can coincidentally be the same route (this is
        // just the existing "speaksBoth" case restated to sit next to the different-route
        // test below for contrast).
        let now = Date()
        let first = BusArrival(route: "22", destination: "Fillmore", arrivalTime: now.addingTimeInterval(240), now: now)
        let second = BusArrival(route: "22", destination: "Downtown", arrivalTime: now.addingTimeInterval(420), now: now)
        let text = CheckFavoriteArrivalIntent.arrivalsDialogText(stopName: "Market & 4th", arrivals: [first, second])
        #expect(text == "The 22 arrives at Market & 4th in 4 minutes, then 7 minutes.")
    }

    @Test func favoriteArrival_twoArrivalsDifferentRoutes_namesSecondRoute() async throws {
        // A favorited stop isn't filtered by route, so the top-two-by-time can be two
        // different routes — the dialog must not imply the second arrival is also `first.route`.
        let now = Date()
        let first = BusArrival(route: "22", destination: "Fillmore", arrivalTime: now.addingTimeInterval(240), now: now)
        let second = BusArrival(route: "5", destination: "Downtown", arrivalTime: now.addingTimeInterval(420), now: now)
        let text = CheckFavoriteArrivalIntent.arrivalsDialogText(stopName: "Market & 4th", arrivals: [first, second])
        #expect(text == "The 22 arrives at Market & 4th in 4 minutes, then the 5 in 7 minutes.")
    }

    @Test func favoriteArrival_noAPIKeyConfigured_performReturnsConfigureDialog() async throws {
        // apiKey already cleared in init()
        let intent = CheckFavoriteArrivalIntent()
        let result = try await intent.perform()
        // `perform()`'s opaque `some IntentResult & ProvidesDialog` return type doesn't itself
        // expose `.dialog` — `ProvidesDialog` is an empty marker protocol, and `dialog` is only
        // reachable on the concrete `IntentResultContainer` struct that `.result(dialog:)`
        // actually produces. Downcast to that concrete type to read it.
        let concrete = try #require(result as? IntentResultContainer<Never, Never, Never, IntentDialog>)
        let dialog = try #require(concrete.dialog)
        #expect(literalText(from: dialog) == "Please configure your 511.org API key in SF Transit Watch settings.")
    }

    @Test func favoriteArrival_noFavorites_returnsNoFavoritesDialog() async throws {
        ConfigurationManager.shared.apiKey = "test-key"
        UserDefaults.standard.removeObject(forKey: "FavoriteStops")
        let intent = CheckFavoriteArrivalIntent()
        let result = try await intent.perform()
        let concrete = try #require(result as? IntentResultContainer<Never, Never, Never, IntentDialog>)
        let dialog = try #require(concrete.dialog)
        #expect(literalText(from: dialog) == "You don't have any favorite stops yet. Add one in SF Transit Watch.")
    }

    // MARK: - CheckRouteArrivalsIntent — dialog text

    @Test func routeArrival_emptyArrivals_returnsNoArrivalsDialog() async throws {
        let text = CheckRouteArrivalsIntent.arrivalsDialogText(routeNumber: "54", stopName: "Geneva & Naples", arrivals: [])
        #expect(text == "No upcoming arrivals for Geneva & Naples right now.")
    }

    @Test func routeArrival_singleArrival_speaksOne() async throws {
        let now = Date()
        let arrival = BusArrival(route: "54", destination: "Outbound", arrivalTime: now.addingTimeInterval(300), now: now)
        let text = CheckRouteArrivalsIntent.arrivalsDialogText(routeNumber: "54", stopName: "Geneva & Naples", arrivals: [arrival])
        #expect(text == "The 54 at Geneva & Naples arrives in 5 minutes.")
    }

    @Test func routeArrival_twoArrivals_speaksBoth() async throws {
        let now = Date()
        let first = BusArrival(route: "54", destination: "Outbound", arrivalTime: now.addingTimeInterval(300), now: now)
        let second = BusArrival(route: "54", destination: "Outbound", arrivalTime: now.addingTimeInterval(900), now: now)
        let text = CheckRouteArrivalsIntent.arrivalsDialogText(routeNumber: "54", stopName: "Geneva & Naples", arrivals: [first, second])
        #expect(text == "The 54 at Geneva & Naples arrives in 5 minutes, then 15 minutes.")
    }

    // MARK: - CheckRouteArrivalsIntent — resolveStop

    @Test func resolveStop_singleCandidate_returnsSingleWithoutNeedingLocation() async throws {
        let stop = BusStop(id: "1", name: "Geneva & Naples", code: "GN", latitude: 37.7, longitude: -122.4)
        let resolution = resolveStop(from: [stop], location: nil)
        guard case .single(let resolved) = resolution else {
            Issue.record("expected .single, got \(resolution)")
            return
        }
        #expect(resolved.id == "1")
    }

    @Test func resolveStop_multipleCandidatesNoLocation_returnsNeedsLocation() async throws {
        let a = BusStop(id: "1", name: "A", code: "A", latitude: 37.7, longitude: -122.4)
        let b = BusStop(id: "2", name: "B", code: "B", latitude: 37.71, longitude: -122.41)
        let resolution = resolveStop(from: [a, b], location: nil)
        guard case .needsLocation = resolution else {
            Issue.record("expected .needsLocation, got \(resolution)")
            return
        }
    }

    @Test func resolveStop_candidatesFarApart_picksNearestWithoutAsking() async throws {
        // 1 degree of latitude is roughly 111km — comfortably over the 50m threshold.
        let near = BusStop(id: "near", name: "Near", code: "N", latitude: 37.7000, longitude: -122.4000)
        let far = BusStop(id: "far", name: "Far", code: "F", latitude: 37.8000, longitude: -122.4000)
        let userLocation = CLLocation(latitude: 37.7001, longitude: -122.4000)
        let resolution = resolveStop(from: [far, near], location: userLocation)
        guard case .single(let resolved) = resolution else {
            Issue.record("expected .single, got \(resolution)")
            return
        }
        #expect(resolved.id == "near")
    }

    @Test func resolveStop_candidatesWithin50Meters_returnsAmbiguous() async throws {
        let a = BusStop(id: "a", name: "A", code: "A", latitude: 37.70000, longitude: -122.40000)
        // ~30m east of `a` at this latitude.
        let b = BusStop(id: "b", name: "B", code: "B", latitude: 37.70000, longitude: -122.39965)
        let userLocation = CLLocation(latitude: 37.70000, longitude: -122.40000)
        let resolution = resolveStop(from: [a, b], location: userLocation)
        guard case .ambiguous(let candidates) = resolution else {
            Issue.record("expected .ambiguous, got \(resolution)")
            return
        }
        #expect(candidates.map(\.id) == ["a", "b"])
    }

    @Test func resolveStop_farApartButRoughlyEquidistantFromUser_returnsSingleNotAmbiguous() async throws {
        // Distinguishes the corrected stop-to-stop distance rule from the old (buggy) rule
        // that compared the *delta* between each candidate's distance from the user. These two
        // stops are ~400m apart from each other (well over the 50m threshold) but each is only
        // ~200m from the user, so the delta between their distances-from-user is tiny — under
        // the old logic that delta alone would have triggered `.ambiguous`. Under the corrected
        // rule (distance between the stops themselves) this must resolve to `.single`, proving
        // the fix actually changed behavior rather than just being cosmetic.
        let east = BusStop(id: "east", name: "East", code: "E", latitude: 37.70000, longitude: -122.397729)
        let west = BusStop(id: "west", name: "West", code: "W", latitude: 37.70000, longitude: -122.402271)
        let userLocation = CLLocation(latitude: 37.70000, longitude: -122.40000)
        let resolution = resolveStop(from: [east, west], location: userLocation)
        guard case .single = resolution else {
            Issue.record("expected .single, got \(resolution)")
            return
        }
    }

    // MARK: - CheckRouteArrivalsIntent — resolveDirection

    @Test func resolveDirection_singleGroup_resolvesWithoutAsking() async throws {
        let arrival = BusArrival(route: "54", destination: "Outbound", arrivalTime: Date(), now: Date())
        let resolution = resolveDirection(requested: nil, groups: ["Outbound": [arrival]])
        guard case .resolved(let key) = resolution else {
            Issue.record("expected .resolved, got \(resolution)")
            return
        }
        #expect(key == "Outbound")
    }

    @Test func resolveDirection_multipleGroupsNoRequest_needsDisambiguation() async throws {
        let arrival = BusArrival(route: "54", destination: "x", arrivalTime: Date(), now: Date())
        let resolution = resolveDirection(requested: nil, groups: ["Inbound": [arrival], "Outbound": [arrival]])
        guard case .needsDisambiguation(let options) = resolution else {
            Issue.record("expected .needsDisambiguation, got \(resolution)")
            return
        }
        #expect(Set(options) == ["Inbound", "Outbound"])
    }

    @Test func resolveDirection_requestedMatchesCaseInsensitively_resolves() async throws {
        let arrival = BusArrival(route: "54", destination: "x", arrivalTime: Date(), now: Date())
        let resolution = resolveDirection(requested: "outbound", groups: ["Inbound": [arrival], "Outbound": [arrival]])
        guard case .resolved(let key) = resolution else {
            Issue.record("expected .resolved, got \(resolution)")
            return
        }
        #expect(key == "Outbound")
    }

    @Test func resolveDirection_requestedNoMatch_listsAvailable() async throws {
        let arrival = BusArrival(route: "54", destination: "x", arrivalTime: Date(), now: Date())
        let resolution = resolveDirection(requested: "sideways", groups: ["Inbound": [arrival], "Outbound": [arrival]])
        guard case .noMatch(let available) = resolution else {
            Issue.record("expected .noMatch, got \(resolution)")
            return
        }
        #expect(available == ["Inbound", "Outbound"])
    }

    // MARK: - CheckRouteArrivalsIntent — perform() gates

    @Test func routeArrival_noAPIKeyConfigured_performReturnsConfigureDialog() async throws {
        // apiKey already cleared in init()
        var intent = CheckRouteArrivalsIntent()
        intent.routeNumber = "54"
        let result = try await intent.perform()
        let concrete = try #require(result as? IntentResultContainer<Never, Never, Never, IntentDialog>)
        let dialog = try #require(concrete.dialog)
        #expect(literalText(from: dialog) == "Please configure your 511.org API key in SF Transit Watch settings.")
    }

    @Test func routeArrival_noFavorites_returnsNoFavoritesDialog() async throws {
        ConfigurationManager.shared.apiKey = "test-key"
        UserDefaults.standard.removeObject(forKey: "FavoriteStops")
        var intent = CheckRouteArrivalsIntent()
        intent.routeNumber = "54"
        let result = try await intent.perform()
        let concrete = try #require(result as? IntentResultContainer<Never, Never, Never, IntentDialog>)
        let dialog = try #require(concrete.dialog)
        #expect(literalText(from: dialog) == "You don't have any favorite stops yet. Add one in SF Transit Watch.")
    }

    // MARK: - CheckRouteArrivalsIntent — Caltrain direction fallback

    @Test func caltrainDirectionLabels_matchesDirectionLabelOutput() async throws {
        #expect(TransitJSON.caltrainDirectionLabels == ["Southbound", "Northbound"])
    }

    @Test func directionArrival_emptyArrivals_returnsNoArrivalsDialog() async throws {
        let text = CheckRouteArrivalsIntent.directionArrivalsDialogText(direction: "Southbound", stopName: "San Mateo", arrivals: [])
        #expect(text == "No upcoming southbound arrivals for San Mateo right now.")
    }

    @Test func directionArrival_singleArrival_speaksOne() async throws {
        let now = Date()
        let arrival = BusArrival(route: "L LOCAL", destination: "Southbound", arrivalTime: now.addingTimeInterval(300), now: now)
        let text = CheckRouteArrivalsIntent.directionArrivalsDialogText(direction: "Southbound", stopName: "San Mateo", arrivals: [arrival])
        #expect(text == "The next southbound train at San Mateo arrives in 5 minutes.")
    }

    @Test func directionArrival_twoArrivals_speaksBoth() async throws {
        let now = Date()
        let first = BusArrival(route: "L LOCAL", destination: "Southbound", arrivalTime: now.addingTimeInterval(300), now: now)
        let second = BusArrival(route: "L LOCAL", destination: "Southbound", arrivalTime: now.addingTimeInterval(900), now: now)
        let text = CheckRouteArrivalsIntent.directionArrivalsDialogText(direction: "Southbound", stopName: "San Mateo", arrivals: [first, second])
        #expect(text == "The next southbound train at San Mateo arrives in 5 minutes, then 15 minutes.")
    }

    @MainActor
    @Test func routeArrival_directionWordWithNoCaltrainFavorites_returnsNoCaltrainFavoritesDialog() async throws {
        ConfigurationManager.shared.apiKey = "test-key"
        let manager = FavoritesManager()
        manager.clearAllFavorites()
        manager.toggleFavorite(BusStop(id: "muni-1", name: "Market & 4th", code: "M4", latitude: 37.7, longitude: -122.4, agency: "SF"))
        defer { manager.clearAllFavorites() }

        var intent = CheckRouteArrivalsIntent()
        intent.routeNumber = "southbound"
        let result = try await intent.perform()
        let concrete = try #require(result as? IntentResultContainer<Never, Never, Never, IntentDialog>)
        let dialog = try #require(concrete.dialog)
        #expect(literalText(from: dialog) == "You don't have any favorite Caltrain stops.")
    }

    // MARK: - CheckRouteArrivalsIntent — favoritesWithArrivalsInDirection

    @Test func favoritesWithArrivalsInDirection_allLookupsFinish_returnsOnlyMatchingStopsInOrder() async throws {
        let now = Date()
        let a = BusStop(id: "a", name: "A", code: "A", latitude: 37.70, longitude: -122.40, agency: "CT")
        let b = BusStop(id: "b", name: "B", code: "B", latitude: 37.71, longitude: -122.41, agency: "CT")
        let c = BusStop(id: "c", name: "C", code: "C", latitude: 37.72, longitude: -122.42, agency: "CT")
        let south = BusArrival(route: "L LOCAL", destination: "Southbound", arrivalTime: now.addingTimeInterval(300), now: now)
        let north = BusArrival(route: "L LOCAL", destination: "Northbound", arrivalTime: now.addingTimeInterval(300), now: now)

        let result = await favoritesWithArrivalsInDirection(among: [a, b, c], direction: "Southbound", timeout: 5) { stop in
            switch stop.id {
            // Finish out of order so the index-restoring sort is actually exercised.
            case "a": try? await Task.sleep(nanoseconds: 40_000_000); return [south]
            case "b": return [north]
            default: return [south]
            }
        }
        #expect(result?.map(\.stop.id) == ["a", "c"])
        #expect(result?.first?.arrivals.map(\.id) == [south.id])
    }

    /// Mirrors `favoritesServingRoute_deadlineFires_lookupsKeepRunningUncancelled`'s regression
    /// guard for the same reason: an abandoned-but-cancelled `fetchArrivals` call must not be
    /// able to poison the (shorter-lived, but still real) arrivals cache.
    @Test func favoritesWithArrivalsInDirection_deadlineFires_lookupsKeepRunningUncancelled() async throws {
        let stop = BusStop(id: "1", name: "San Mateo", code: "SM", latitude: 37.5, longitude: -122.3, agency: "CT")
        let probe = LookupProbe()

        let started = Date()
        let result = await favoritesWithArrivalsInDirection(among: [stop], direction: "Southbound", timeout: 0.1) { _ in
            try? await Task.sleep(nanoseconds: 400_000_000)
            probe.finish(cancelled: Task.isCancelled)
            return []
        }

        #expect(result == nil, "the deadline must win and produce the try-again dialog")
        #expect(Date().timeIntervalSince(started) < 0.35, "perform() must not block on the abandoned lookup")

        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(probe.completed, "the abandoned lookup must still run to completion")
        #expect(probe.sawCancellation == false, "the abandoned lookup must never be cancelled")
    }

    /// End-to-end against the real `TransitAPI` + `TransitJSON.decodeArrivals`: proves the
    /// Caltrain direction fallback actually lines up with what `directionLabel` produces for a
    /// real StopMonitoring payload, not just with hand-built `BusArrival` fixtures above.
    @MainActor
    @Test func favoritesWithArrivalsInDirection_realCaltrainPayload_matchesSouthboundLabel() async throws {
        let api = TransitAPI()
        let mock = MockURLSession()
        api.urlSession = mock
        ConfigurationManager.shared.apiKey = "test-key"
        ConfigurationManager.shared.workerBaseURL = ""
        ConfigurationManager.shared.workerToken = ""

        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let realtime = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[
          {"MonitoredVehicleJourney":{"LineRef":"CT:L_LOCAL","DirectionRef":"IB","MonitoredCall":{"ExpectedDepartureTime":"\(isoIn5)"},"OnwardCalls":{}}}
        ]}}}
        """.data(using: .utf8)!
        mock.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: realtime)

        let stop = BusStop(id: "caltrain-1", name: "San Mateo", code: "SM", latitude: 37.5, longitude: -122.3, agency: "CT")
        let result = await favoritesWithArrivalsInDirection(among: [stop], direction: "Southbound", timeout: 5) {
            await api.fetchArrivals(for: $0.id, agency: $0.agency)
        }
        #expect(result?.map(\.stop.id) == ["caltrain-1"])
        #expect(result?.first?.arrivals.first?.route == "L LOCAL")

        ConfigurationManager.shared.apiKey = ""
    }

    // MARK: - CheckRouteArrivalsIntent — favoritesServingRoute

    @Test func favoritesServingRoute_allLookupsFinish_returnsMatchesInOriginalOrder() async throws {
        let a = BusStop(id: "a", name: "A", code: "A", latitude: 37.70, longitude: -122.40)
        let b = BusStop(id: "b", name: "B", code: "B", latitude: 37.71, longitude: -122.41)
        let c = BusStop(id: "c", name: "C", code: "C", latitude: 37.72, longitude: -122.42)
        let result = await favoritesServingRoute(among: [a, b, c], routeNumber: "54", timeout: 5) { stop in
            // Finish out of order so the index-restoring sort is actually exercised.
            switch stop.id {
            case "a": try? await Task.sleep(nanoseconds: 60_000_000); return ["54"]
            case "b": return ["38", "38R"]
            default: try? await Task.sleep(nanoseconds: 20_000_000); return ["54R", "54"]
            }
        }
        #expect(result?.map(\.id) == ["a", "c"])
    }

    /// Regression guard. The route-matching phase used to be a `withTaskGroup` raced against a
    /// timeout via `withTimeout`, whose `group.cancelAll()` cancelled every still-in-flight
    /// `fetchRoutes` call when the deadline won. That mattered because a cancelled lookup does
    /// not fail loudly — it returns `[]`, which `fetchRoutes` then caches for 7 days as "this
    /// stop serves no routes". One slow-network Siri invocation could therefore make "when is
    /// the next 54" answer "none of your favorites serve route 54" for a week. The deadline must
    /// abandon the *wait* only; the lookups have to keep running.
    @Test func favoritesServingRoute_deadlineFires_lookupsKeepRunningUncancelled() async throws {
        let stop = BusStop(id: "1", name: "Geneva & Naples", code: "GN", latitude: 37.7, longitude: -122.4)
        let probe = LookupProbe()

        let started = Date()
        let result = await favoritesServingRoute(among: [stop], routeNumber: "54", timeout: 0.1) { _ in
            // `try?` on purpose: if this task were cancelled, the sleep returns early and the
            // probe records `sawCancellation`, which is exactly the failure we're guarding
            // against — rather than the sleep silently swallowing it.
            try? await Task.sleep(nanoseconds: 400_000_000)
            probe.finish(cancelled: Task.isCancelled)
            return ["54"]
        }

        #expect(result == nil, "the deadline must win and produce the try-again dialog")
        #expect(Date().timeIntervalSince(started) < 0.35, "perform() must not block on the abandoned lookup")
        #expect(probe.completed == false, "sanity: the lookup is still in flight at this point")

        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(probe.completed, "the abandoned lookup must still run to completion")
        #expect(probe.sawCancellation == false, "the abandoned lookup must never be cancelled")
    }

    /// End-to-end version of the above against the real `TransitAPI` + `StopRoutesCache`: after
    /// the deadline fires, the background lookup must land the stop's *actual* routes in the
    /// 7-day cache. Under the old `cancelAll()` behaviour the mock session's delay would throw
    /// `CancellationError`, `fetchScheduledDepartures` would swallow it as `[]`, and the cache
    /// would be poisoned with an empty route list.
    @MainActor
    @Test func favoritesServingRoute_deadlineFires_backgroundLookupCachesRealRoutes() async throws {
        let api = TransitAPI()
        let mock = MockURLSession()
        api.urlSession = mock
        let cache = StopRoutesCache(defaults: UserDefaults(suiteName: "RouteLookupTimeout-\(UUID().uuidString)")!)
        api.stopRoutesCache = cache
        ConfigurationManager.shared.apiKey = "test-key"
        ConfigurationManager.shared.workerBaseURL = ""
        ConfigurationManager.shared.workerToken = ""

        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let timetable = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"SF:54","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"Outbound"}}}
        ]}}}}
        """.data(using: .utf8)!
        mock.setMockResponse(for: URL(string: "https://api.511.org/transit/StopTimetable")!, data: timetable)
        mock.delaySeconds = 0.4

        let stop = BusStop(id: "1234", name: "Geneva & Naples", code: "GN", latitude: 37.7, longitude: -122.4)
        let result = await favoritesServingRoute(among: [stop], routeNumber: "54", timeout: 0.1) {
            await api.fetchRoutes(for: $0.id, agency: $0.agency)
        }
        #expect(result == nil)
        #expect(cache.routes(for: "1234", agency: "SF") == nil, "sanity: nothing cached yet at the deadline")

        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(cache.routes(for: "1234", agency: "SF") == ["54"], "cache must hold the real routes, not a cancelled []")

        ConfigurationManager.shared.apiKey = ""
    }
}
