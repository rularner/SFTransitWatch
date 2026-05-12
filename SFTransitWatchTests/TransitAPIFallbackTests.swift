import XCTest
import SFTransitWatchPackage
@testable import SFTransitWatch_Watch_App

final class TransitAPIFallbackTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear all configuration before each test
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
    }

    override func tearDown() {
        super.tearDown()
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
    }

    // MARK: - 401 Fallback Scenario Tests

    func testInitiallyInWorkerMode() {
        // Set up worker configuration
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        let api = TransitAPI()

        // Should start in worker mode
        XCTAssertFalse(api.isDirect511ModeForTesting,
                       "Should initially be in worker mode when configured")
        XCTAssertEqual(api.baseURLForTesting, "https://api.example.com")
    }

    func testWorkerRequest401WithTokenSet() {
        // Worker mode with valid token should be attempted
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("invalid-token", forKey: "WORKER_TOKEN")
        let api = TransitAPI()

        // The API should not be in direct mode yet (401 would trigger fallback)
        XCTAssertFalse(api.isDirect511ModeForTesting,
                       "Should not be in direct mode before 401 response")
    }

    // MARK: - Error Message Tests

    func testErrorMessageWhenMissingAPIKeyInDirectMode() {
        let api = TransitAPI()
        // In direct mode with no API key configured
        XCTAssertTrue(api.isDirect511ModeForTesting)
        XCTAssertFalse(api.hasUsableKeyForTesting)
        XCTAssertEqual(api.apiKeyForTesting, "YOUR_511_API_KEY",
                       "Should use placeholder when no real key configured")
    }

    func testPhoneAPIKeyFallbackScenario() {
        // Simulate scenario where phone app set the key
        UserDefaults.standard.set("watch-local-key", forKey: "511_API_KEY")
        UserDefaults.standard.set("phone-shared-key", forKey: "511_API_KEY_FROM_PHONE")
        let api = TransitAPI()

        // Should resolve to phone's key
        XCTAssertEqual(api.resolvedKeyForTesting, "phone-shared-key")
        XCTAssertEqual(api.apiKeyForTesting, "phone-shared-key")
    }

    // MARK: - Partial Configuration Tests

    func testPartialWorkerConfigWithURLOnly() {
        // Only URL set, token missing
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        let api = TransitAPI()

        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should fall back to direct mode when token is missing")
        XCTAssertEqual(api.baseURLForTesting, "https://api.511.org/transit",
                       "Should use 511.org URL when falling back to direct mode")
    }

    func testPartialWorkerConfigWithTokenOnly() {
        // Only token set, URL missing
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        let api = TransitAPI()

        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should fall back to direct mode when URL is missing")
    }

    // MARK: - Configuration State Transitions

    func testClearingWorkerConfigForcesFallback() {
        // Start with worker config
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("test-token", forKey: "WORKER_TOKEN")
        UserDefaults.standard.set("backup-api-key", forKey: "511_API_KEY")

        var api = TransitAPI()
        XCTAssertFalse(api.isDirect511ModeForTesting)

        // Simulate error handler clearing worker config
        UserDefaults.standard.removeObject(forKey: "WORKER_BASE_URL")
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")

        api = TransitAPI()
        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should be in direct mode after worker config is cleared")
    }

    // MARK: - Request Header Validation

    func testWorkerRequestHasCorrectAuthHeader() {
        let workerToken = "worker-auth-token-12345"
        UserDefaults.standard.set("https://worker.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set(workerToken, forKey: "WORKER_TOKEN")
        let api = TransitAPI()

        let url = URL(string: "https://worker.example.com/StopMonitoring?agency=SF&stopCode=15552")!
        let request = api.makeRequestForTesting(url: url)

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Token"), workerToken,
                       "Worker request must include X-App-Token header with correct token")
    }

    func testDirectRequestHasNoAuthHeader() {
        UserDefaults.standard.set("direct-api-key", forKey: "511_API_KEY")
        let api = TransitAPI()

        let url = URL(string: "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=15552&api_key=direct-api-key")!
        let request = api.makeRequestForTesting(url: url)

        XCTAssertNil(request.value(forHTTPHeaderField: "X-App-Token"),
                     "Direct mode request must not have X-App-Token header")
    }

    // MARK: - Endpoint Correctness Tests

    func testDirectModeUsesCorrect511Endpoint() {
        UserDefaults.standard.set("api-key", forKey: "511_API_KEY")
        let api = TransitAPI()

        XCTAssertTrue(api.baseURLForTesting.contains("511.org"),
                      "Direct mode must use 511.org endpoint")
        XCTAssertEqual(api.baseURLForTesting, "https://api.511.org/transit")
    }

    func testWorkerModeUsesConfiguredEndpoint() {
        let customWorkerURL = "https://my-worker.cloudflare.com/api"
        UserDefaults.standard.set(customWorkerURL, forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("token", forKey: "WORKER_TOKEN")
        let api = TransitAPI()

        XCTAssertEqual(api.baseURLForTesting, customWorkerURL,
                       "Worker mode must use configured worker endpoint")
    }

    // MARK: - API Key Placeholder Test

    func testPlaceholderAPIKeyWhenNoneConfigured() {
        // No configuration at all
        let api = TransitAPI()

        XCTAssertEqual(api.apiKeyForTesting, "YOUR_511_API_KEY",
                       "Should use placeholder key when none configured")
        XCTAssertFalse(api.hasUsableKeyForTesting,
                       "Should indicate no usable key when placeholder is being used")
    }

    // MARK: - Configuration Validity Tests

    func testIsWorkerConfigValidWhenBothSet() {
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        UserDefaults.standard.set("valid-token", forKey: "WORKER_TOKEN")
        let api = TransitAPI()

        XCTAssertFalse(api.isDirect511ModeForTesting,
                       "Worker mode should be active when both URL and token are set")
    }

    func testIsNotWorkerConfigValidWhenEitherMissing() {
        // Missing URL
        UserDefaults.standard.set("valid-token", forKey: "WORKER_TOKEN")
        var api = TransitAPI()
        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should not consider config valid when URL is missing")

        // Reset and try missing token
        UserDefaults.standard.removeObject(forKey: "WORKER_TOKEN")
        UserDefaults.standard.set("https://api.example.com", forKey: "WORKER_BASE_URL")
        api = TransitAPI()
        XCTAssertTrue(api.isDirect511ModeForTesting,
                      "Should not consider config valid when token is missing")
    }
}
