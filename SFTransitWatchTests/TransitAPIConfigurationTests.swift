import XCTest
import SFTransitWatchPackage
@testable import SFTransitWatch_Watch_App

final class TransitAPIConfigurationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear all configuration before each test
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
    }

    override func tearDown() {
        super.tearDown()
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
    }

    // MARK: - Configuration Mode Tests

    func testDirectModeWhenWorkerConfigMissing() {
        let api = TransitAPI()
        // Without worker config, should be in direct 511 mode
        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should be in direct mode when worker token and URL are empty")
    }

    func testDirectModeWhenWorkerTokenMissing() {
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        let api = TransitAPI()
        // Missing token means not fully configured
        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should be in direct mode when worker token is missing")
    }

    func testDirectModeWhenWorkerURLMissing() {
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        let api = TransitAPI()
        // Missing URL means not fully configured
        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should be in direct mode when worker URL is missing")
    }

    func testWorkerModeWhenFullyConfigured() {
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        let api = TransitAPI()
        // With both token and URL configured, should use worker mode
        XCTAssertFalse(api.isDirect511ModeForTesting,
                       "Should be in worker mode when both token and URL are configured")
    }

    // MARK: - Base URL Selection Tests

    func testBaseURLIsDefaultWhenDirect() {
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")
        let api = TransitAPI()
        XCTAssertEqual(api.baseURLForTesting, "https://api.511.org/transit",
                       "Should use 511.org API when in direct mode")
    }

    func testBaseURLIsWorkerURLWhenConfigured() {
        let workerURL = "https://worker.example.com/transit"
        UserDefaults.standard.set(workerURL, forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        let api = TransitAPI()
        XCTAssertEqual(api.baseURLForTesting, workerURL,
                       "Should use worker URL when in worker mode")
    }

    // MARK: - API Key Resolution Tests

    func testAPIKeyResolvesFromStoredKey() {
        UserDefaults.standard.set("stored-key-123", forKey: "511_API_KEY")
        let api = TransitAPI()
        XCTAssertEqual(api.apiKeyForTesting, "stored-key-123",
                       "Should resolve API key from stored key")
    }

    func testAPIKeyPrefersPhonesKeyWhenAvailable() {
        UserDefaults.standard.set("stored-key-123", forKey: "511_API_KEY")
        UserDefaults.standard.set("phone-key-456", forKey: "511_API_KEY_FROM_PHONE")
        let api = TransitAPI()
        XCTAssertEqual(api.apiKeyForTesting, "phone-key-456",
                       "Should prefer phone API key over stored key")
    }

    func testAPIKeyDefaultsToPlaceholder() {
        let api = TransitAPI()
        XCTAssertEqual(api.apiKeyForTesting, "YOUR_511_API_KEY",
                       "Should use placeholder when no API key is configured")
    }

    // MARK: - App Token (Worker Authentication) Tests

    func testAppTokenIsNilInDirectMode() {
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")
        let api = TransitAPI()
        XCTAssertNil(api.appTokenForTesting,
                     "Should not have app token in direct mode")
    }

    func testAppTokenIsSetInWorkerMode() {
        let testToken = "worker-token-xyz"
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set(testToken, forKey: "WORKER_TOKEN")
        let api = TransitAPI()
        XCTAssertEqual(api.appTokenForTesting, testToken,
                       "Should have app token in worker mode")
    }

    // MARK: - Query Parameter Tests

    func testDirectModeIncludesAPIKeyInQueryParams() {
        UserDefaults.standard.set("test-api-key", forKey: "511_API_KEY")
        let api = TransitAPI()

        // Simulate building a URL for direct mode
        var components = URLComponents(string: "https://api.511.org/transit/StopMonitoring")
        var queryItems = [
            URLQueryItem(name: "agency", value: "SF"),
            URLQueryItem(name: "stopCode", value: "15552")
        ]

        // In direct mode, API key should be added
        if api.isDirect511ModeForTesting {
            queryItems.append(URLQueryItem(name: "api_key", value: api.apiKeyForTesting))
        }

        components?.queryItems = queryItems
        let url = components?.url?.absoluteString ?? ""

        XCTAssertTrue(url.contains("api_key=test-api-key"),
                      "Direct mode should include api_key query parameter")
    }

    func testWorkerModeExcludesAPIKeyFromQueryParams() {
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        UserDefaults.standard.set("test-api-key", forKey: "511_API_KEY")
        let api = TransitAPI()

        // Simulate building a URL for worker mode
        var components = URLComponents(string: "https://api.example.com/StopMonitoring")
        var queryItems = [
            URLQueryItem(name: "agency", value: "SF"),
            URLQueryItem(name: "stopCode", value: "15552")
        ]

        // In worker mode, API key should NOT be added
        if api.isDirect511ModeForTesting {
            queryItems.append(URLQueryItem(name: "api_key", value: api.apiKeyForTesting))
        }

        components?.queryItems = queryItems
        let url = components?.url?.absoluteString ?? ""

        XCTAssertFalse(url.contains("api_key="),
                       "Worker mode should not include api_key query parameter")
    }

    // MARK: - HTTP Header Tests

    func testDirectModeRequestDoesNotHaveAppTokenHeader() {
        UserDefaults.standard.set("test-key", forKey: "511_API_KEY")
        let api = TransitAPI()

        let url = URL(string: "https://api.511.org/transit/StopMonitoring")!
        let request = api.makeRequestForTesting(url: url)

        XCTAssertNil(request.value(forHTTPHeaderField: "X-App-Token"),
                     "Direct mode request should not have X-App-Token header")
    }

    func testWorkerModeRequestHasAppTokenHeader() {
        let testToken = "worker-token-xyz"
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set(testToken, forKey: "WORKER_TOKEN")
        let api = TransitAPI()

        let url = URL(string: "https://api.example.com/StopMonitoring")!
        let request = api.makeRequestForTesting(url: url)

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Token"), testToken,
                       "Worker mode request should have X-App-Token header with the token")
    }

    // MARK: - Configuration Persistence Tests

    func testAPIKeyPersistsViaAppStorage() {
        let testKey = "persistent-api-key"
        UserDefaults.standard.set(testKey, forKey: "511_API_KEY")

        // Create a new instance to simulate app relaunch
        let api = TransitAPI()

        XCTAssertEqual(api.apiKeyForTesting, testKey,
                       "API key should persist across TransitAPI instances")
    }

    func testWorkerConfigurationPersistsViaAppStorage() {
        let testURL = "https://persistent-worker.example.com"
        let testToken = "persistent-token"
        UserDefaults.standard.set(testURL, forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set(testToken, forKey: "WORKER_TOKEN")

        // Create a new instance to simulate app relaunch
        let api = TransitAPI()

        XCTAssertEqual(api.baseURLForTesting, testURL,
                       "Worker URL should persist across TransitAPI instances")
        XCTAssertEqual(api.appTokenForTesting, testToken,
                       "Worker token should persist across TransitAPI instances")
    }

    // MARK: - Error Handling Tests

    func testMissingAPIKeyErrorInDirectMode() {
        let api = TransitAPI()
        // No API key set, should be in direct mode

        // Simulate the check that happens in fetchArrivals
        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should be in direct mode when no configuration")
        XCTAssertFalse(api.hasUsableKeyForTesting,
                       "Should not have usable key when none is configured")
    }

    func testPhoneAPIKeyTakesPrecedence() {
        UserDefaults.standard.set("watch-key", forKey: "511_API_KEY")
        UserDefaults.standard.set("phone-key", forKey: "511_API_KEY_FROM_PHONE")
        let api = TransitAPI()

        XCTAssertEqual(api.resolvedKeyForTesting, "phone-key",
                       "Phone API key should take precedence over watch key")
    }

    // MARK: - Configuration Change Tests

    func testSwitchFromDirectToWorkerMode() {
        // Start in direct mode with API key
        UserDefaults.standard.set("direct-api-key", forKey: "511_API_KEY")
        var api = TransitAPI()
        XCTAssertTrue(api.isDirect511ModeForTesting)

        // Switch to worker mode
        UserDefaults.standard.set("https://worker.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("worker-token", forKey: "WORKER_TOKEN")

        api = TransitAPI()
        XCTAssertFalse(api.isDirect511ModeForTesting,
                       "Should switch to worker mode when worker config is added")
        XCTAssertEqual(api.baseURLForTesting, "https://worker.example.com")
    }

    func testSwitchFromWorkerToDirectMode() {
        // Start in worker mode
        UserDefaults.standard.set("https://worker.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("worker-token", forKey: "WORKER_TOKEN")
        UserDefaults.standard.set("fallback-api-key", forKey: "511_API_KEY")
        var api = TransitAPI()
        XCTAssertFalse(api.isDirect511ModeForTesting)

        // Clear worker config (simulates fallback)
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")

        api = TransitAPI()
        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should switch to direct mode when worker config is cleared")
        XCTAssertEqual(api.baseURLForTesting, "https://api.511.org/transit")
    }
}
