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
}
