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

        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")
    }

    @MainActor
    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
    }

    /// When worker returns 401, API should retry with direct mode
    @MainActor
    func testFallbacksToDirectModeOn401() async {
        let workerURL = URL(string: "https://worker.example.com/")!
        let directURL = URL(string: "https://api.511.org/")!

        UserDefaults.standard.set("https://worker.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("worker-token", forKey: "WORKER_TOKEN")

        // Worker returns 401
        let workerResponse = HTTPURLResponse(url: workerURL, statusCode: 401, httpVersion: nil, headerFields: nil)!
        mockSession.responses[workerURL] = (Data(), workerResponse)

        // Direct mode succeeds
        let xmlData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let directResponse = HTTPURLResponse(url: directURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        mockSession.responses[directURL] = (xmlData, directResponse)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        // Should have made 2 requests: worker then direct
        XCTAssertEqual(mockSession.requestCount(), 2, "Should retry after 401")
    }

    /// Missing API key shows proper error
    @MainActor
    func testMissingAPIKeyShowsError() async {
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")

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
}
