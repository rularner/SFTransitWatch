import XCTest
import SFTransitWatchPackage
@testable import SFTransitWatch_Watch_App

/// Tests for critical error handling: 401 fallback from worker to direct mode.
final class TransitAPIFallbackTests: XCTestCase {

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

    /// When worker returns 401, API should retry with direct mode
    @MainActor
    func testFallbacksToDirectModeOn401() async {
        let workerURL = URL(string: "https://worker.example.com/")!
        let directURL = URL(string: "https://api.511.org/")!

        ConfigurationManager.shared.workerBaseURL = "https://worker.example.com"
        ConfigurationManager.shared.workerToken = "worker-token"

        // Worker returns 401
        let workerResponse = HTTPURLResponse(url: workerURL, statusCode: 401, httpVersion: nil, headerFields: nil)!
        mockSession.responses[workerURL] = (Data(), workerResponse)

        // Direct mode succeeds with a non-empty arrival (avoids triggering StopTimetable fallback)
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let jsonData = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[
          {"MonitoredVehicleJourney":{
            "LineRef":"SF:38","DirectionRef":"IB","VehicleRef":null,
            "MonitoredCall":{"ExpectedDepartureTime":"\(isoIn5)"},
            "OnwardCalls":{}
          }}
        ]}}}
        """.data(using: .utf8)!
        let directResponse = HTTPURLResponse(url: directURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        mockSession.responses[directURL] = (jsonData, directResponse)

        _ = await api.fetchArrivals(for: "15552", agency: "SF")

        // Should have made exactly 2 requests: worker (401) then direct 511.org (success)
        XCTAssertEqual(mockSession.requestCount(), 2, "Should retry after 401")
    }

    /// Missing API key shows proper error
    @MainActor
    func testMissingAPIKeyShowsError() async {
        ConfigurationManager.shared.apiKey = ""

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty)
        XCTAssertEqual(api.errorMessage, "Please configure your 511.org API key in Settings")
    }

    /// Network errors are handled
    @MainActor
    func testNetworkErrorIsHandled() async {
        let url = URL(string: "https://api.511.org/")!
        mockSession.setMockError(for: url, error: URLError(.networkConnectionLost))

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty)
        XCTAssertNotNil(api.errorMessage)
    }

    /// HTTP 5xx errors are reported
    @MainActor
    func testHTTP5xxErrorReported() async {
        let url = URL(string: "https://api.511.org/")!
        let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
        mockSession.responses[url] = (Data(), response)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty)
        XCTAssertEqual(api.errorMessage, "511.org returned HTTP 503")
    }

    @MainActor
    func testEmptyStopMonitoringTriggersTimetableFallback() async {
        // StopMonitoring returns HTTP 200 with empty visits
        let emptyMonitoring = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopMonitoring")!,
            data: emptyMonitoring
        )

        // StopTimetable returns two scheduled arrivals
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let isoIn10 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let timetableData = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"Local Weekday","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"San Francisco"}}},
          {"TargetedVehicleJourney":{"LineRef":"Limited Weekday","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn10)","DestinationDisplay":"San Francisco"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(
            for: URL(string: "https://api.511.org/transit/StopTimetable")!,
            data: timetableData
        )

        let arrivals = await api.fetchArrivals(for: "70021", agency: "CT")

        XCTAssertEqual(arrivals.count, 2, "Should return scheduled arrivals as fallback")
        XCTAssertFalse(arrivals[0].isRealTime, "Scheduled arrivals must have isRealTime: false")
        XCTAssertFalse(arrivals[1].isRealTime)
        XCTAssertEqual(mockSession.requestCount(), 2, "Must make StopMonitoring then StopTimetable requests")
    }

    @MainActor
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
        XCTAssertEqual(mockSession.requestCount(), 1, "Must NOT call StopTimetable when real-time data is present")
    }

    /// A non-200 StopMonitoring response must fall back to the schedule, same as an empty
    /// real-time result — previously the watch just surfaced an error here.
    @MainActor
    func testHTTPErrorFallsBackToScheduleWhenAvailable() async {
        let monitoringURL = URL(string: "https://api.511.org/transit/StopMonitoring")!
        mockSession.responses[monitoringURL] = (Data(), HTTPURLResponse(url: monitoringURL, statusCode: 503, httpVersion: nil, headerFields: nil)!)

        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let timetableData = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"Local Weekday","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"SF"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopTimetable")!, data: timetableData)

        let arrivals = await api.fetchArrivals(for: "70021", agency: "CT")

        XCTAssertEqual(arrivals.count, 1)
        XCTAssertFalse(arrivals[0].isRealTime)
        XCTAssertNil(api.errorMessage, "should clear the error once the schedule fallback succeeds")
    }

    /// A thrown network error on StopMonitoring must also fall back to the (cached) schedule.
    /// Warms the cache first: MockURLSession's error matching is host-wide (not path-specific),
    /// so once StopMonitoring is made to throw, a live StopTimetable fetch would throw too —
    /// exactly the scenario the schedule cache exists to avoid hitting.
    @MainActor
    func testNetworkErrorFallsBackToCachedScheduleWithoutRefetching() async {
        let emptyMonitoring = """
        {"ServiceDelivery":{"StopMonitoringDelivery":{"MonitoredStopVisit":[]}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: emptyMonitoring)
        let isoIn5 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let timetableData = """
        {"Siri":{"ServiceDelivery":{"StopTimetableDelivery":{"TimetabledStopVisit":[
          {"TargetedVehicleJourney":{"LineRef":"Local Weekday","DirectionRef":"N","TargetedCall":{"AimedDepartureTime":"\(isoIn5)","DestinationDisplay":"SF"}}}
        ]}}}}
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopTimetable")!, data: timetableData)

        let warm = await api.fetchArrivals(for: "70021", agency: "CT")   // warms the schedule cache
        XCTAssertEqual(warm.count, 1)
        XCTAssertEqual(mockSession.requestCount(), 2)

        api.now = { Date().addingTimeInterval(60) }   // still well within the 24h schedule TTL
        mockSession.setMockError(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, error: URLError(.networkConnectionLost))

        let arrivals = await api.fetchArrivals(for: "70021", agency: "CT")

        XCTAssertEqual(arrivals.count, 1)
        XCTAssertFalse(arrivals[0].isRealTime)
        XCTAssertNil(api.errorMessage, "should clear the error once the cached-schedule fallback succeeds")
        XCTAssertEqual(mockSession.requestCount(), 3, "StopMonitoring retry only — schedule served from cache, no new StopTimetable call")
    }

    // MARK: - Scheduled-departures client-side cache

    @MainActor
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

    @MainActor
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

    @MainActor
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
}
