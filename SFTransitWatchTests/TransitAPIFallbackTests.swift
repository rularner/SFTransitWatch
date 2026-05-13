import XCTest
import SFTransitWatchPackage
@testable import SFTransitWatch_Watch_App

final class TransitAPIFallbackTests: XCTestCase {

    var api: TransitAPI!
    var mockSession: MockURLSession!

    override func setUp() {
        super.setUp()
        api = TransitAPI()
        mockSession = MockURLSession()
        api.urlSession = mockSession

        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
    }

    // MARK: - 401 Fallback Scenario Tests

    func testInitiallyInWorkerMode() async {
        let workerURL = "https://api.example.com"
        UserDefaults.standard.set(workerURL, forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")

        // Set up successful response on direct mode as fallback
        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let directURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        mockSession.setMockResponse(for: directURL, data: mockData, statusCode: 200)

        // Set 401 on worker URL to trigger fallback
        let workerRequestURL = URL(string: "https://api.example.com/StopMonitoring?agency=SF&stopCode=15552")!
        mockSession.setMockResponse(for: workerRequestURL, data: Data(), statusCode: 401)

        await api.fetchArrivals(for: "15552", agency: "SF")

        // Should have made two requests: first to worker, then to direct
        XCTAssertEqual(mockSession.requestCount(), 2, "Should make two requests: worker then fallback to direct")
    }

    func testWorkerRequest401WithTokenSet() async {
        let workerURL = "https://api.example.com"
        UserDefaults.standard.set(workerURL, forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("invalid-token", forKey: "WORKER_TOKEN")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let directURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        mockSession.setMockResponse(for: directURL, data: mockData, statusCode: 200)

        let workerRequestURL = URL(string: "https://api.example.com/StopMonitoring?agency=SF&stopCode=15552")!
        mockSession.setMockResponse(for: workerRequestURL, data: Data(), statusCode: 401)

        await api.fetchArrivals(for: "15552", agency: "SF")

        // First request should be to worker URL
        let firstRequest = mockSession.requests.first
        XCTAssertTrue(firstRequest?.url?.host == "api.example.com", "Should initially try worker URL")
    }

    // MARK: - Error Message Tests

    func testErrorMessageWhenMissingAPIKeyInDirectMode() async {
        // Don't set API key
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty, "Should return empty when API key missing")
        XCTAssertEqual(api.errorMessage, "Please configure your 511.org API key in Settings", "Should show API key configuration error")
    }

    func testPhoneAPIKeyFallbackScenario() async {
        UserDefaults.standard.set("watch-local-key", forKey: "511_API_KEY")
        UserDefaults.standard.set("phone-shared-key", forKey: "511_API_KEY_FROM_PHONE")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=phone-shared-key")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        let request = mockSession.lastRequest()
        XCTAssertTrue(request?.url?.absoluteString.contains("api_key=phone-shared-key") ?? false, "Should resolve to phone's key")
    }

    // MARK: - Partial Configuration Tests

    func testPartialWorkerConfigWithURLOnly() async {
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        let request = mockSession.lastRequest()
        XCTAssertTrue(request?.url?.host == "api.511.org", "Should fall back to direct mode when token is missing")
    }

    func testPartialWorkerConfigWithTokenOnly() async {
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        let request = mockSession.lastRequest()
        XCTAssertTrue(request?.url?.host == "api.511.org", "Should fall back to direct mode when URL is missing")
    }

    func testErrorMessageOnNetworkFailure() async {
        let url = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        mockSession.setMockError(for: url, error: URLError(.networkConnectionLost))

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty, "Should return empty arrivals on network error")
        XCTAssertNotNil(api.errorMessage, "Should set error message on network failure")
    }

    func testErrorMessageOn4xxResponse() async {
        let url = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        let response = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
        mockSession.responses[url] = (Data(), response)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty, "Should return empty on 4xx error")
        XCTAssertEqual(api.errorMessage, "511.org returned HTTP 400", "Should report HTTP error code")
    }

    func testErrorMessageOn5xxResponse() async {
        let url = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
        mockSession.responses[url] = (Data(), response)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty, "Should return empty on 5xx error")
        XCTAssertEqual(api.errorMessage, "511.org returned HTTP 503", "Should report HTTP error code")
    }
}
