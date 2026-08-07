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
        api.stopRoutesCache = StopRoutesCache(defaults: UserDefaults(suiteName: "PhoneTransitAPITests-\(UUID().uuidString)")!)
        ConfigurationManager.shared.apiKey = "test-key"
    }

    override func tearDown() {
        super.tearDown()
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.workerToken = ""
        ConfigurationManager.shared.workerBaseURL = ""
    }

    func testFetchRoutesCacheMissDerivesDistinctSortedRoutesAndCaches() async {
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let isoIn10 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let isoIn15 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(900))
        let timetableData = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"SF:38R","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"Downtown"}}},
          {"TargetedVehicleJourney":{"LineRef":"SF:38","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn10)","DestinationDisplay":"Downtown"}}},
          {"TargetedVehicleJourney":{"LineRef":"SF:38","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn15)","DestinationDisplay":"Downtown"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopTimetable")!,
            data: timetableData
        )

        let routes = await api.fetchRoutes(for: "1234", agency: "SF")

        XCTAssertEqual(routes, ["38", "38R"])
        XCTAssertEqual(mockSession.requestCount(), 1)

        // Second call is a cache hit: no additional request.
        let cachedRoutes = await api.fetchRoutes(for: "1234", agency: "SF")
        XCTAssertEqual(cachedRoutes, ["38", "38R"])
        XCTAssertEqual(mockSession.requestCount(), 1)
    }

    func testFetchRoutesEmptyTimetableCachesEmptyArray() async {
        let emptyTimetable = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopTimetable")!,
            data: emptyTimetable
        )

        let routes = await api.fetchRoutes(for: "1234", agency: "SF")
        XCTAssertEqual(routes, [])
        XCTAssertEqual(mockSession.requestCount(), 1)

        let cachedRoutes = await api.fetchRoutes(for: "1234", agency: "SF")
        XCTAssertEqual(cachedRoutes, [])
        XCTAssertEqual(mockSession.requestCount(), 1)
    }

    /// Regression: the phone's regex-based XML fallback parser
    /// (parseXMLArrivals) assigns `destination` from the raw DirectionRef
    /// capture group. It must map through directionLabel, same as the JSON
    /// decode path, so "IB"/"OB" never leak to the UI.
    func testParseArrivalsWithValidXMLMapsDirectionRefToOutbound() async {
        let isoDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ServiceDelivery>
          <StopMonitoringDelivery>
            <MonitoredStopVisit>
              <MonitoredVehicleJourney>
                <LineRef>38</LineRef>
                <DirectionRef>OB</DirectionRef>
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
        XCTAssertEqual(arrivals[0].destination, "Outbound")
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

    func testFetchJourneyStops_returnsStopsFromTimetable() async {
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now.addingTimeInterval(300))
        let h = comps.hour ?? 10
        let m = comps.minute ?? 5
        let pad = { (n: Int) in String(format: "%02d", n) }
        let t1 = "\(pad(h)):\(pad(m)):00"
        let t2 = "\(pad((h * 60 + m + 5) / 60 % 24)):\(pad((m + 5) % 60)):00"

        let timetableData = """
        {
          "Content": {
            "TimetableFrame": [{
              "Name": "38:IB:WEEKDAY",
              "vehicleJourneys": {
                "ServiceJourney": [{
                  "JourneyPatternView": {"DirectionRef":{"ref":"IB"}},
                  "calls": {"Call": [
                    {"ScheduledStopPointRef":{"ref":"15725"},"Arrival":{"Time":"\(t1)","DaysOffset":"0"},"Departure":{"Time":"\(t1)","DaysOffset":"0"},"order":"1"},
                    {"ScheduledStopPointRef":{"ref":"15730"},"Arrival":{"Time":"\(t2)","DaysOffset":"0"},"Departure":{"Time":"\(t2)","DaysOffset":"0"},"order":"2"}
                  ]},
                  "id": "trip-1"
                }]
              }
            }]
          }
        }
        """.data(using: .utf8)!
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/Timetable")!,
            data: timetableData
        )

        let stops = await api.fetchJourneyStops(
            route: "38",
            destination: "IB",
            boardingStopId: "15725",
            boardingTime: now.addingTimeInterval(300),
            agency: "SF"
        )

        XCTAssertEqual(stops.count, 2)
        XCTAssertEqual(stops[0].id, "15725")
        XCTAssertFalse(stops[0].isRealTime)
    }

    func testFetchJourneyStops_noMatch_returnsEmpty() async {
        let timetableData = """
        {"Content": {"TimetableFrame": [{"Name": "38:IB:WEEKDAY","vehicleJourneys":{"ServiceJourney":[]}}]}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/Timetable")!,
            data: timetableData
        )

        let stops = await api.fetchJourneyStops(
            route: "38",
            destination: "IB",
            boardingStopId: "99999",
            boardingTime: Date(),
            agency: "SF"
        )

        XCTAssertEqual(stops.count, 0)
    }

    func testStopMonitoringRequestsJSONFormat() async {
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let realtime = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[
          {"MonitoredVehicleJourney":{"LineRef":"SF:38","DirectionRef":"IB","MonitoredCall":{"ExpectedDepartureTime":"\(isoIn5)"},"OnwardCalls":{}}}
        ]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: realtime)

        _ = await api.fetchArrivals(for: "15552", agency: "SF")

        let url = mockSession.recordedRequests().first!.url!.absoluteString
        XCTAssertTrue(url.contains("format=json"), "expected format=json in \(url)")
    }

    func testFetchArrivalsThrottlesRepeatCalls() async {
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let realtime = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[
          {"MonitoredVehicleJourney":{"LineRef":"SF:38","DirectionRef":"IB","MonitoredCall":{"ExpectedDepartureTime":"\(isoIn5)"},"OnwardCalls":{}}}
        ]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: realtime)

        _ = await api.fetchArrivals(for: "15552", agency: "SF")
        _ = await api.fetchArrivals(for: "15552", agency: "SF")
        XCTAssertEqual(mockSession.requestCount(), 1, "second call within throttle window is served from cache")
    }

    func testFetchArrivalsCoalescesConcurrentCalls() async {
        mockSession.delaySeconds = 1
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let realtime = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[
          {"MonitoredVehicleJourney":{"LineRef":"SF:38","DirectionRef":"IB","MonitoredCall":{"ExpectedDepartureTime":"\(isoIn5)"},"OnwardCalls":{}}}
        ]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: realtime)

        async let a = api.fetchArrivals(for: "15552", agency: "SF")
        async let b = api.fetchArrivals(for: "15552", agency: "SF")
        _ = await [a, b]
        XCTAssertEqual(mockSession.requestCount(), 1, "concurrent calls for the same stop issue one request")
    }

    // MARK: - 429 backoff + keep-last / schedule fallback

    func testRateLimitedFallsBackToScheduleWhenNoRecentData() async {
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: Data("{}".utf8), statusCode: 429)
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let timetable = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"Local Weekday","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"SF"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopTimetable")!, data: timetable)

        let arrivals = await api.fetchArrivals(for: "70021", agency: "CT")

        XCTAssertEqual(arrivals.count, 1)
        XCTAssertFalse(arrivals[0].isRealTime)
        XCTAssertNotNil(api.softBanner)
        XCTAssertGreaterThan(api.pollInterval, 30, "poll interval backs off after a 429")
    }

    func testSuccessResetsBackoff() async {
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let realtime = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[
          {"MonitoredVehicleJourney":{"LineRef":"SF:38","DirectionRef":"IB","MonitoredCall":{"ExpectedDepartureTime":"\(isoIn5)"},"OnwardCalls":{}}}
        ]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: realtime)

        _ = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertEqual(api.pollInterval, 30)
        XCTAssertNil(api.softBanner)
    }

    func testRateLimitedKeepsRecentRealtimeData() async {
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let realtime = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[
          {"MonitoredVehicleJourney":{"LineRef":"SF:38","DirectionRef":"IB","MonitoredCall":{"ExpectedDepartureTime":"\(isoIn5)"},"OnwardCalls":{}}}
        ]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: realtime)
        _ = await api.fetchArrivals(for: "15552", agency: "SF")   // caches realtime

        api.now = { Date().addingTimeInterval(30) }               // past 20s throttle, within 120s keep-last
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: Data("{}".utf8), statusCode: 429)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertEqual(arrivals.count, 1)
        XCTAssertTrue(arrivals[0].isRealTime, "kept the recent live data instead of the schedule")
        XCTAssertNotNil(api.softBanner)
        XCTAssertEqual(mockSession.requestCount(), 2, "one initial load + one 429; no schedule fetch")
    }

    // MARK: - Scheduled-departures client-side cache

    func testFetchScheduledDeparturesCachesAcrossRepeatedCalls() async {
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let timetable = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"Local Weekday","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"SF"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopTimetable")!, data: timetable)

        let first = await api.fetchScheduledDepartures(for: "70021", agency: "CT")
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(mockSession.requestCount(), 1)

        let second = await api.fetchScheduledDepartures(for: "70021", agency: "CT")
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(mockSession.requestCount(), 1, "second call within the 24h TTL should be served from cache")
    }

    func testFetchScheduledDeparturesCacheExpiresAfter24Hours() async {
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let timetable = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"Local Weekday","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"SF"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopTimetable")!, data: timetable)

        _ = await api.fetchScheduledDepartures(for: "70021", agency: "CT")
        XCTAssertEqual(mockSession.requestCount(), 1)

        api.now = { Date().addingTimeInterval(24 * 60 * 60 + 1) }
        _ = await api.fetchScheduledDepartures(for: "70021", agency: "CT")
        XCTAssertEqual(mockSession.requestCount(), 2, "cache should have expired after 24h")
    }

    func testFetchScheduledDeparturesRecomputesMinutesAwayOnCacheHit() async throws {
        let isoIn10 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let timetable = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"SF:38","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn10)","DestinationDisplay":"Downtown"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopTimetable")!, data: timetable)

        let first = await api.fetchScheduledDepartures(for: "70021", agency: "SF")
        let arrivalTime = try XCTUnwrap(first.first?.arrivalTime)

        let laterNow = Date().addingTimeInterval(240)   // 4 minutes later, still within the 24h TTL
        api.now = { laterNow }
        let second = await api.fetchScheduledDepartures(for: "70021", agency: "SF")

        let expectedMinutesAway = max(0, Int(arrivalTime.timeIntervalSince(laterNow) / 60))
        XCTAssertEqual(second.first?.minutesAway, expectedMinutesAway, "cache hit must recompute minutesAway against the current time")
        XCTAssertNotEqual(second.first?.minutesAway, first.first?.minutesAway, "must not reuse the frozen minutesAway from the first decode")
        XCTAssertEqual(mockSession.requestCount(), 1, "still served from cache")
    }

    /// A thrown network error on StopMonitoring must fall back to the (cached) schedule, same
    /// as an empty real-time result — not just report an error.
    func testNetworkErrorFallsBackToCachedScheduleWithoutRefetching() async {
        let emptyMonitoring = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: emptyMonitoring)
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let timetable = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"Local Weekday","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"SF"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopTimetable")!, data: timetable)

        let warm = await api.fetchArrivals(for: "70021", agency: "CT")   // warms the schedule cache
        XCTAssertEqual(warm.count, 1)
        XCTAssertEqual(mockSession.requestCount(), 2)

        // Past the 120s keep-last window but well within the 24h schedule cache.
        api.now = { Date().addingTimeInterval(150) }
        mockSession.setMockError(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, error: URLError(.networkConnectionLost))

        let arrivals = await api.fetchArrivals(for: "70021", agency: "CT")

        XCTAssertEqual(arrivals.count, 1)
        XCTAssertFalse(arrivals[0].isRealTime)
        XCTAssertNil(api.errorMessage, "should clear the error once the cached-schedule fallback succeeds")
        XCTAssertEqual(mockSession.requestCount(), 3, "StopMonitoring retry only — schedule served from cache, no new StopTimetable call")
    }

    // MARK: - Backend failure signaling (X-Cache-Status: ERROR)

    func testBackendErrorStatusSurfacesSoftBannerEvenAtHTTP200() async {
        // Mirrors CloudflareWorker/src/gtfsrt/proxy.ts's fallback response when the reader
        // Lambda fails and there's no cache entry: HTTP 200, empty MonitoredStopVisit[], but
        // tagged X-Cache-Status: ERROR (not MISS) so the client can tell "backend is down"
        // apart from a genuine "no buses scheduled" empty result.
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopMonitoring")!,
            data: Data("{\"ServiceDelivery\":{\"StopMonitoringDelivery\":{\"MonitoredStopVisit\":[]}}}".utf8),
            headers: ["X-Cache-Status": "ERROR"]
        )
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopTimetable")!,
            data: Data("{}".utf8)
        )

        _ = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertEqual(api.softBanner, "Live updates unavailable — showing scheduled times")
    }

    func testGenuineEmptyResultDoesNotSurfaceBackendErrorBanner() async {
        // Same empty MonitoredStopVisit[] shape, but a normal cache MISS — a real "no buses
        // right now" result, not a backend failure. Must not show the error banner.
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopMonitoring")!,
            data: Data("{\"ServiceDelivery\":{\"StopMonitoringDelivery\":{\"MonitoredStopVisit\":[]}}}".utf8),
            headers: ["X-Cache-Status": "MISS"]
        )
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopTimetable")!,
            data: Data("{}".utf8)
        )

        _ = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertNil(api.softBanner)
    }
}
