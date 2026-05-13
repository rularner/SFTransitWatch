import XCTest
import SFTransitWatchPackage
@testable import SFTransitWatch_Watch_App

final class TransitAPIParsingTests: XCTestCase {

    var api: TransitAPI!
    var mockSession: MockURLSession!

    @MainActor
    override func setUp() {
        super.setUp()
        api = TransitAPI()
        mockSession = MockURLSession()
        api.urlSession = mockSession

        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-key-123", forKey: "511_API_KEY")
    }

    @MainActor
    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
    }

    @MainActor
    func testParseArrivalsExtractsRouteAndTime() async throws {
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

        let url = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key-123")!
        mockSession.setMockResponse(for: url, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertFalse(arrivals.isEmpty, "Should parse at least one arrival")
        XCTAssertEqual(arrivals[0].route, "38")
        XCTAssertGreaterThan(arrivals[0].minutesAway, 0)
    }

    @MainActor
    func testParseArrivalsEmptyXMLReturnsEmpty() async throws {
        let xml = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let url = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key-123")!
        mockSession.setMockResponse(for: url, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")
        XCTAssertTrue(arrivals.isEmpty)
    }

    @MainActor
    func testParseStopsExtractsNameAndCoordinates() async throws {
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

        let url = URL(string: "https://api.511.org/transit/Stops?operator_id=SF&lat=37.7858&lon=-122.4064&latitude=37.7858&longitude=-122.4064&radius=1000&api_key=test-key-123")!
        mockSession.setMockResponse(for: url, data: xml)

        let stops = await api.fetchNearbyStops(latitude: 37.7858, longitude: -122.4064)

        XCTAssertFalse(stops.isEmpty, "Should parse at least one stop")
        XCTAssertEqual(stops[0].id, "15552")
        XCTAssertEqual(stops[0].latitude, 37.7858, accuracy: 0.0001)
        XCTAssertEqual(stops[0].longitude, -122.4064, accuracy: 0.0001)
    }

    @MainActor
    func testParseStopsEmptyXMLReturnsEmpty() async throws {
        let xml = "<StopPlaces></StopPlaces>".data(using: .utf8)!
        let url = URL(string: "https://api.511.org/transit/Stops?operator_id=SF&lat=37.7858&lon=-122.4064&latitude=37.7858&longitude=-122.4064&radius=1000&api_key=test-key-123")!
        mockSession.setMockResponse(for: url, data: xml)

        let stops = await api.fetchNearbyStops(latitude: 37.7858, longitude: -122.4064)
        XCTAssertTrue(stops.isEmpty)
    }

    @MainActor
    func testParseArrivalsIgnoresUTF8BOM() async throws {
        let iso = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ServiceDelivery>
          <StopMonitoringDelivery>
            <MonitoredStopVisit>
              <MonitoredVehicleJourney>
                <LineRef>14</LineRef>
                <DirectionRef>IB</DirectionRef>
                <MonitoredCall>
                  <ExpectedDepartureTime>\(iso)</ExpectedDepartureTime>
                </MonitoredCall>
              </MonitoredVehicleJourney>
            </MonitoredStopVisit>
          </StopMonitoringDelivery>
        </ServiceDelivery>
        """
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(body.data(using: .utf8)!)

        let url = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key-123")!
        mockSession.setMockResponse(for: url, data: data)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")
        XCTAssertEqual(arrivals.first?.route, "14")
    }
}
