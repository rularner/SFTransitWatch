import XCTest
import SFTransitWatchPackage
@testable import SFTransitWatch_Watch_App

final class TransitAPIConfigurationTests: XCTestCase {

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
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
    }

    // MARK: - Configuration Mode Tests

    func testDirectModeWhenWorkerConfigMissing() async {
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        // Verify it called the direct 511 URL, not a worker URL
        let request = mockSession.lastRequest()
        XCTAssertNotNil(request, "Should have made a request")
        XCTAssertTrue(request?.url?.host == "api.511.org", "Should use 511.org in direct mode")
    }

    func testDirectModeWhenWorkerTokenMissing() async {
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        // Without token, should fall back to direct mode
        let request = mockSession.lastRequest()
        XCTAssertTrue(request?.url?.host == "api.511.org", "Should fall back to direct mode when token is missing")
    }

    func testDirectModeWhenWorkerURLMissing() async {
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        // Without URL, should fall back to direct mode
        let request = mockSession.lastRequest()
        XCTAssertTrue(request?.url?.host == "api.511.org", "Should fall back to direct mode when URL is missing")
    }

    func testWorkerModeWhenFullyConfigured() async {
        let workerURL = "https://api.example.com"
        UserDefaults.standard.set(workerURL, forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.example.com/StopMonitoring?agency=SF&stopCode=15552")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        // Should use worker URL
        let request = mockSession.lastRequest()
        XCTAssertTrue(request?.url?.host == "api.example.com", "Should use worker URL when fully configured")
        XCTAssertTrue(request?.value(forHTTPHeaderField: "X-App-Token") == "test-token", "Should include worker token header")
    }

    // MARK: - API Key Resolution Tests

    func testAPIKeyResolvesFromStoredKey() async {
        UserDefaults.standard.set("stored-key-123", forKey: "511_API_KEY")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=stored-key-123")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        let request = mockSession.lastRequest()
        XCTAssertTrue(request?.url?.absoluteString.contains("api_key=stored-key-123") ?? false, "Should resolve API key from stored key")
    }

    func testAPIKeyPrefersPhonesKeyWhenAvailable() async {
        UserDefaults.standard.set("stored-key-123", forKey: "511_API_KEY")
        UserDefaults.standard.set("phone-key-456", forKey: "511_API_KEY_FROM_PHONE")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=phone-key-456")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        let request = mockSession.lastRequest()
        XCTAssertTrue(request?.url?.absoluteString.contains("api_key=phone-key-456") ?? false, "Should prefer phone API key over stored key")
    }

    func testMissingAPIKeyShowsError() async {
        let result = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(result.isEmpty, "Should return empty arrivals when API key is missing")
        XCTAssertEqual(api.errorMessage, "Please configure your 511.org API key in Settings", "Should set error message about missing key")
    }

    // MARK: - Query Parameter Tests

    func testDirectModeIncludesAPIKeyInQueryParams() async {
        UserDefaults.standard.set("test-api-key", forKey: "511_API_KEY")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-api-key")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        let request = mockSession.lastRequest()
        XCTAssertTrue(request?.url?.absoluteString.contains("api_key=test-api-key") ?? false, "Direct mode should include api_key query parameter")
    }

    func testWorkerModeExcludesAPIKeyFromQueryParams() async {
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        UserDefaults.standard.set("test-api-key", forKey: "511_API_KEY")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.example.com/StopMonitoring?agency=SF&stopCode=15552")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        let request = mockSession.lastRequest()
        XCTAssertFalse(request?.url?.absoluteString.contains("api_key=") ?? true, "Worker mode should not include api_key query parameter")
    }

    // MARK: - HTTP Header Tests

    func testDirectModeRequestDoesNotHaveAppTokenHeader() async {
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=test-key")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        let request = mockSession.lastRequest()
        XCTAssertNil(request?.value(forHTTPHeaderField: "X-App-Token"), "Direct mode request should not have X-App-Token header")
    }

    func testWorkerModeRequestIncludesAppTokenHeader() async {
        let testToken = "worker-token-xyz"
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set(testToken, forKey: "WORKER_TOKEN")
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")

        let mockData = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        let expectedURL = URL(string: "https://api.example.com/StopMonitoring?agency=SF&stopCode=15552")!
        mockSession.setMockResponse(for: expectedURL, data: mockData)

        await api.fetchArrivals(for: "15552", agency: "SF")

        let request = mockSession.lastRequest()
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-App-Token"), testToken, "Worker mode request should have X-App-Token header")
    }
}
