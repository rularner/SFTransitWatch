import XCTest
@testable import SFTransitWatch
import SFTransitWatchPackage

final class PhoneTransitAPITests: XCTestCase {
    var api: TransitAPI!
    var mockSession: MockURLSession!

    override func setUp() {
        super.setUp()
        api = TransitAPI()
        mockSession = MockURLSession()
        api.urlSession = mockSession
        ConfigurationManager.shared.apiKey = "test-key"
    }

    override func tearDown() {
        super.tearDown()
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.workerToken = ""
        ConfigurationManager.shared.workerBaseURL = ""
    }

    func testSearchStopsByExactCode() async {
        let xml = """
        <StopPlaces>
          <StopPlace>
            <StopPlaceRef>15552</StopPlaceRef>
            <StopPlaceName>Castro Station</StopPlaceName>
            <Location><Latitude>37.762</Latitude><Longitude>-122.435</Longitude></Location>
          </StopPlace>
          <StopPlace>
            <StopPlaceRef>13000</StopPlaceRef>
            <StopPlaceName>Market St &amp; 8th St</StopPlaceName>
            <Location><Latitude>37.780</Latitude><Longitude>-122.410</Longitude></Location>
          </StopPlace>
        </StopPlaces>
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let results = await api.searchStops(query: "15552", agencies: ["SF"])

        XCTAssertNotNil(results)
        XCTAssertEqual(results?.count, 1)
        XCTAssertEqual(results?.first?.code, "15552")
        XCTAssertEqual(results?.first?.name, "Castro Station")
    }

    func testSearchStopsByNameSubstring() async {
        let xml = """
        <StopPlaces>
          <StopPlace>
            <StopPlaceRef>15552</StopPlaceRef>
            <StopPlaceName>Castro Station</StopPlaceName>
            <Location><Latitude>37.762</Latitude><Longitude>-122.435</Longitude></Location>
          </StopPlace>
          <StopPlace>
            <StopPlaceRef>13000</StopPlaceRef>
            <StopPlaceName>Market St &amp; 8th St</StopPlaceName>
            <Location><Latitude>37.780</Latitude><Longitude>-122.410</Longitude></Location>
          </StopPlace>
        </StopPlaces>
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let results = await api.searchStops(query: "castro", agencies: ["SF"])

        XCTAssertEqual(results?.count, 1)
        XCTAssertEqual(results?.first?.name, "Castro Station")
    }

    func testSearchStopsEmptyQueryMakesNoRequests() async {
        let results = await api.searchStops(query: "   ", agencies: ["SF"])

        XCTAssertEqual(results, [BusStop]())
        XCTAssertEqual(mockSession.requestCount(), 0)
    }

    func testSearchStopsMultiAgencyMakesTwoRequests() async {
        let xml = """
        <StopPlaces>
          <StopPlace>
            <StopPlaceRef>15552</StopPlaceRef>
            <StopPlaceName>Castro Station</StopPlaceName>
            <Location><Latitude>37.762</Latitude><Longitude>-122.435</Longitude></Location>
          </StopPlace>
        </StopPlaces>
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let results = await api.searchStops(query: "15552", agencies: ["SF", "BA"])

        XCTAssertEqual(mockSession.requestCount(), 2, "One request per agency")
        XCTAssertEqual(results?.count, 2, "id+agency dedup: 15552|SF and 15552|BA are distinct")
    }

    func testSearchStopsReturnsNilWhenAllAgenciesFail() async {
        mockSession.setMockError(for: URL(string: "https://api.511.org")!,
                                 error: URLError(.notConnectedToInternet))

        let results = await api.searchStops(query: "castro", agencies: ["SF"])

        XCTAssertNil(results)
    }
}
