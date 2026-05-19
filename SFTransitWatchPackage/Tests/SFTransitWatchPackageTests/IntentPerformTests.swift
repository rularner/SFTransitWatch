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
}
