import XCTest
import SFTransitWatchPackage
@testable import SFTransitWatch_Watch_App

/// Tests for TransitAPI data parsing with simple mock responses.
/// Focuses on verifying XML/JSON parsing works correctly.
final class TransitAPIParsingTests: XCTestCase {

    var api: TransitAPI!
    var mockSession: MockURLSession!

    @MainActor
    override func setUp() {
        super.setUp()
        api = TransitAPI()
        mockSession = MockURLSession()
        api.urlSession = mockSession

        // Set API key via ConfigurationManager (not UserDefaults)
        ConfigurationManager.shared.apiKey = "test-key"
    }

    @MainActor
    override func tearDown() {
        super.tearDown()
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.workerToken = ""
        ConfigurationManager.shared.workerBaseURL = ""
    }

    @MainActor
    func testParseArrivalsWithValidXML() async {
        let isoDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ServiceDelivery>
          <StopMonitoringDelivery>
            <MonitoredStopVisit>
              <MonitoredVehicleJourney>
                <LineRef>38</LineRef>
                <DirectionRef>IB</DirectionRef>
                <MonitoredCall>
                  <ExpectedDepartureTime>\(isoDate)</ExpectedDepartureTime>
                </MonitoredCall>
              </MonitoredVehicleJourney>
            </MonitoredStopVisit>
          </StopMonitoringDelivery>
        </ServiceDelivery>
        """.data(using: .utf8)!

        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertFalse(arrivals.isEmpty)
        XCTAssertEqual(arrivals[0].route, "38")
    }

    @MainActor
    func testParseArrivalsWithEmptyXML() async {
        let xml = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty)
    }

    @MainActor
    func testParseStopsWithValidXML() async {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <StopPlaces>
          <StopPlace>
            <StopPlaceRef>15552</StopPlaceRef>
            <StopPlaceName>Market St &amp; 4th St</StopPlaceName>
            <Location>
              <Latitude>37.7858</Latitude>
              <Longitude>-122.4064</Longitude>
            </Location>
          </StopPlace>
        </StopPlaces>
        """.data(using: .utf8)!

        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let stops = await api.fetchNearbyStops(latitude: 37.7858, longitude: -122.4064)

        XCTAssertFalse(stops.isEmpty)
        XCTAssertEqual(stops[0].id, "15552")
    }

    @MainActor
    func testParseStopsWithEmptyXML() async {
        let xml = "<StopPlaces></StopPlaces>".data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let stops = await api.fetchNearbyStops(latitude: 37.7858, longitude: -122.4064)

        XCTAssertTrue(stops.isEmpty)
    }
}
