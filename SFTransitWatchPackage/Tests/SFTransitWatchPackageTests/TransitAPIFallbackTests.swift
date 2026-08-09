import XCTest
@testable import SFTransitWatchPackage

/// Tests for critical error handling: 401 fallback from worker to direct mode, plus
/// error-message plumbing for missing keys, network errors, and HTTP errors.
///
/// Migrated from the watch app's `TransitAPIFallbackTests.swift`. Several tests from that
/// file were dropped here as exact duplicates of coverage already ported into
/// `TransitAPITests.swift` (Task 3) — see the migration report for the full list.
@MainActor
final class TransitAPIFallbackTests: XCTestCase {

    var api: TransitAPI!
    var mockSession: MockURLSession!

    override func setUp() async throws {
        try await super.setUp()
        api = TransitAPI()
        mockSession = MockURLSession()
        api.urlSession = mockSession

        // Set API key via ConfigurationManager (not UserDefaults)
        ConfigurationManager.shared.apiKey = "test-key"
    }

    override func tearDown() async throws {
        try await super.tearDown()
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.workerToken = ""
        ConfigurationManager.shared.workerBaseURL = ""
    }

    /// When worker returns 401, API should retry with direct mode
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
    func testMissingAPIKeyShowsError() async {
        ConfigurationManager.shared.apiKey = ""

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty)
        XCTAssertEqual(api.errorMessage, "Please configure your 511.org API key in Settings")
    }

    /// Network errors are handled when no cached/scheduled fallback is available.
    func testNetworkErrorIsHandled() async {
        let url = URL(string: "https://api.511.org/")!
        mockSession.setMockError(for: url, error: URLError(.networkConnectionLost))

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty)
        XCTAssertNotNil(api.errorMessage)
    }

    /// HTTP 5xx errors are reported when the schedule fallback also fails (mock's error/response
    /// matching is host-wide here, so the same 503 covers both StopMonitoring and StopTimetable).
    func testHTTP5xxErrorReported() async {
        let url = URL(string: "https://api.511.org/")!
        let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
        mockSession.responses[url] = (Data(), response)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty)
        XCTAssertEqual(api.errorMessage, "511.org returned HTTP 503")
    }

    /// A non-200 StopMonitoring response must fall back to the schedule when one is available,
    /// rather than surfacing an error.
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
}
