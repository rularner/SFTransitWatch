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

    // MARK: - Filter toggle (race condition regression)

    /// Each enabled agency produces exactly one API request.
    /// Regression: rapid filter toggles previously caused stale-task results to overwrite
    /// newer results because multiple unstructured Tasks raced to write nearbyStops.
    func testFetchNearbyStopsOneRequestPerAgency() async {
        let emptyXML = "<StopPlaces></StopPlaces>".data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: emptyXML)

        _ = await api.fetchNearbyStops(latitude: 37.762, longitude: -122.435, agencies: ["SF", "AC", "SC"])

        XCTAssertEqual(mockSession.requestCount(), 3, "One Stops request per enabled agency")
    }

    func testFetchNearbyStopsNoAgenciesMakesNoRequests() async {
        _ = await api.fetchNearbyStops(latitude: 37.762, longitude: -122.435, agencies: [])

        XCTAssertEqual(mockSession.requestCount(), 0, "No requests when all agencies are filtered out")
    }

    /// Cancelling a fetchNearbyStops task in flight (simulating a filter toggle that supersedes
    /// a prior slow load) causes the task to exit before completing any requests.
    func testFetchNearbyStopsRespectsTaskCancellation() async {
        mockSession.delaySeconds = 5

        let task = Task { @MainActor in
            await self.api.fetchNearbyStops(latitude: 37.762, longitude: -122.435, agencies: ["SF"])
        }
        task.cancel()
        _ = await task.value

        XCTAssertEqual(mockSession.requestCount(), 0, "Cancelled task should not complete any requests")
    }

    func testEmptyStopMonitoringTriggersTimetableFallback() async {
        let emptyMonitoring = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopMonitoring")!,
            data: emptyMonitoring
        )
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let timetableData = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"Local Weekday","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"San Francisco"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopTimetable")!,
            data: timetableData
        )

        let arrivals = await api.fetchArrivals(for: "70021", agency: "CT")

        XCTAssertEqual(arrivals.count, 1)
        XCTAssertFalse(arrivals[0].isRealTime)
        XCTAssertEqual(mockSession.requestCount(), 2)
    }

    func testNonEmptyStopMonitoringSkipsTimetable() async {
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let realtime = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[
          {"MonitoredVehicleJourney":{
            "LineRef":"SF:38","DirectionRef":"IB","VehicleRef":null,
            "MonitoredCall":{"ExpectedDepartureTime":"\(isoIn5)"},
            "OnwardCalls":{}
          }}
        ]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopMonitoring")!,
            data: realtime
        )

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertEqual(arrivals.count, 1)
        XCTAssertTrue(arrivals[0].isRealTime)
        XCTAssertEqual(mockSession.requestCount(), 1)
    }
}
