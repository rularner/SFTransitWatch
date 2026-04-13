import XCTest
@testable import SFTransitWatch_Watch_App

final class TransitAPIParsingTests: XCTestCase {

    // MARK: - Arrivals XML parsing

    func testParseArrivalsExtractsRouteAndTime() throws {
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

        let api = TransitAPI()
        let arrivals = try api.parseArrivalsForTesting(data: xml)
        XCTAssertFalse(arrivals.isEmpty, "Should parse at least one arrival")
        XCTAssertEqual(arrivals[0].route, "38")
        XCTAssertGreaterThan(arrivals[0].minutesAway, 0)
    }

    func testParseArrivalsEmptyXMLReturnsSampleData() throws {
        let xml = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let api = TransitAPI()
        let arrivals = try api.parseArrivalsForTesting(data: xml)
        // Falls back to sample data when no matches found
        XCTAssertFalse(arrivals.isEmpty)
    }

    // MARK: - Stops XML parsing

    func testParseStopsExtractsNameAndCoordinates() throws {
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

        let api = TransitAPI()
        let stops = try api.parseStopsForTesting(data: xml)
        XCTAssertFalse(stops.isEmpty, "Should parse at least one stop")
        XCTAssertEqual(stops[0].id, "15552")
        XCTAssertEqual(stops[0].latitude, 37.7858, accuracy: 0.0001)
        XCTAssertEqual(stops[0].longitude, -122.4064, accuracy: 0.0001)
    }

    func testParseStopsEmptyXMLReturnsSampleData() throws {
        let xml = "<StopPlaces></StopPlaces>".data(using: .utf8)!
        let api = TransitAPI()
        let stops = try api.parseStopsForTesting(data: xml)
        XCTAssertFalse(stops.isEmpty)
    }
}
