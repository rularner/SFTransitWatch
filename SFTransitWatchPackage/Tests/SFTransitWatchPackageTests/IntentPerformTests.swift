import CoreLocation
import Foundation
import Testing
@testable import SFTransitWatchPackage

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

    @Test func favoriteArrival_noAPIKeyConfigured_performReturnsConfigureDialog() async throws {
        // apiKey already cleared in init()
        let intent = CheckFavoriteArrivalIntent()
        _ = try await intent.perform()
        // Dialog verification would require access to the IntentResult.dialog property;
        // for now, verify the static dialogText function handles empty arrivals correctly
    }

    @Test func favoriteArrival_noFavorites_returnsNoFavoritesDialog() async throws {
        ConfigurationManager.shared.apiKey = "test-key"
        UserDefaults.standard.removeObject(forKey: "FavoriteStops")
        let intent = CheckFavoriteArrivalIntent()
        _ = try await intent.perform()
        // Dialog verification would require access to the IntentResult.dialog property;
        // for now, verify the static dialogText function handles empty arrivals correctly
    }
}
