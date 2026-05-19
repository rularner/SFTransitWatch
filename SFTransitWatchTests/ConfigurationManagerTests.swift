import XCTest
import SFTransitWatchPackage

final class ConfigurationManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear app group storage before each test
        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            userDefaults.removeObject(forKey: "511_API_KEY")
            userDefaults.removeObject(forKey: "WORKER_TOKEN")
            userDefaults.removeObject(forKey: "WORKER_BASE_URL")
        }
    }

    override func tearDown() {
        super.tearDown()
        // Clean up after each test
        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            userDefaults.removeObject(forKey: "511_API_KEY")
            userDefaults.removeObject(forKey: "WORKER_TOKEN")
            userDefaults.removeObject(forKey: "WORKER_BASE_URL")
        }
    }

    // MARK: - API Key Persistence Tests

    @MainActor
    func testAPIKeyPersistsInAppGroupsStorage() {
        let testKey = "test-api-key-12345"
        ConfigurationManager.shared.apiKey = testKey

        // Verify it persists by checking the underlying UserDefaults
        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            let storedValue = userDefaults.string(forKey: "511_API_KEY")
            XCTAssertEqual(storedValue, testKey,
                           "API key should persist in app group UserDefaults")
        }
    }

    @MainActor
    func testAPIKeyRetrievalFromAppGroupsStorage() {
        let testKey = "persistent-key-xyz"

        // Set directly in app group storage
        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            userDefaults.set(testKey, forKey: "511_API_KEY")
        }

        // Create new manager instance and verify it reads the same value
        let manager = ConfigurationManager.shared
        XCTAssertEqual(manager.apiKey, testKey,
                       "ConfigurationManager should read API key from app group storage")
    }

    // MARK: - Worker Configuration Persistence Tests

    @MainActor
    func testWorkerTokenPersistsInAppGroupsStorage() {
        let testToken = "worker-token-abc123"
        ConfigurationManager.shared.workerToken = testToken

        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            let storedValue = userDefaults.string(forKey: "WORKER_TOKEN")
            XCTAssertEqual(storedValue, testToken,
                           "Worker token should persist in app group UserDefaults")
        }
    }

    @MainActor
    func testWorkerURLPersistsInAppGroupsStorage() {
        let testURL = "https://worker.example.com/api"
        ConfigurationManager.shared.workerBaseURL = testURL

        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            let storedValue = userDefaults.string(forKey: "WORKER_BASE_URL")
            XCTAssertEqual(storedValue, testURL,
                           "Worker URL should persist in app group UserDefaults")
        }
    }

    // MARK: - setWorkerConfig Method Tests

    @MainActor
    func testSetWorkerConfigPersistsBothValues() {
        let testURL = "https://my-worker.example.com"
        let testToken = "my-worker-token"

        ConfigurationManager.shared.setWorkerConfig(url: testURL, token: testToken)

        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            let storedURL = userDefaults.string(forKey: "WORKER_BASE_URL")
            let storedToken = userDefaults.string(forKey: "WORKER_TOKEN")

            XCTAssertEqual(storedURL, testURL,
                           "setWorkerConfig should persist the URL")
            XCTAssertEqual(storedToken, testToken,
                           "setWorkerConfig should persist the token")
        }
    }

    @MainActor
    func testSetWorkerConfigUpdatesBothProperties() {
        let testURL = "https://new-worker.example.com"
        let testToken = "new-worker-token"

        ConfigurationManager.shared.setWorkerConfig(url: testURL, token: testToken)

        XCTAssertEqual(ConfigurationManager.shared.workerBaseURL, testURL,
                       "workerBaseURL should be updated by setWorkerConfig")
        XCTAssertEqual(ConfigurationManager.shared.workerToken, testToken,
                       "workerToken should be updated by setWorkerConfig")
    }

    // MARK: - clearWorkerConfig Method Tests

    @MainActor
    func testClearWorkerConfigRemovesBothValues() {
        // Set initial values
        ConfigurationManager.shared.setWorkerConfig(
            url: "https://worker.example.com",
            token: "test-token"
        )

        // Clear the configuration
        ConfigurationManager.shared.clearWorkerConfig()

        XCTAssertEqual(ConfigurationManager.shared.workerToken, "",
                       "workerToken should be empty after clear")
        XCTAssertEqual(ConfigurationManager.shared.workerBaseURL, "",
                       "workerBaseURL should be empty after clear")
    }

    @MainActor
    func testClearWorkerConfigRemovesFromAppGroupsStorage() {
        // Set initial values
        ConfigurationManager.shared.setWorkerConfig(
            url: "https://worker.example.com",
            token: "test-token"
        )

        // Clear the configuration
        ConfigurationManager.shared.clearWorkerConfig()

        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            let storedToken = userDefaults.string(forKey: "WORKER_TOKEN") ?? ""
            let storedURL = userDefaults.string(forKey: "WORKER_BASE_URL") ?? ""

            XCTAssertTrue(storedToken.isEmpty,
                          "Worker token should be cleared from app group storage")
            XCTAssertTrue(storedURL.isEmpty,
                          "Worker URL should be cleared from app group storage")
        }
    }

    // MARK: - isWorkerConfigured Property Tests

    @MainActor
    func testIsWorkerConfiguredWhenBothSet() {
        ConfigurationManager.shared.setWorkerConfig(
            url: "https://worker.example.com",
            token: "valid-token"
        )

        XCTAssertTrue(ConfigurationManager.shared.isWorkerConfigured,
                      "Should be configured when both token and URL are set")
    }

    @MainActor
    func testIsNotWorkerConfiguredWhenTokenMissing() {
        ConfigurationManager.shared.workerBaseURL = "https://worker.example.com"
        ConfigurationManager.shared.workerToken = ""

        XCTAssertFalse(ConfigurationManager.shared.isWorkerConfigured,
                       "Should not be configured when token is empty")
    }

    @MainActor
    func testIsNotWorkerConfiguredWhenURLMissing() {
        ConfigurationManager.shared.workerToken = "valid-token"
        ConfigurationManager.shared.workerBaseURL = ""

        XCTAssertFalse(ConfigurationManager.shared.isWorkerConfigured,
                       "Should not be configured when URL is empty")
    }

    @MainActor
    func testIsNotWorkerConfiguredWhenBothMissing() {
        ConfigurationManager.shared.clearWorkerConfig()

        XCTAssertFalse(ConfigurationManager.shared.isWorkerConfigured,
                       "Should not be configured when both token and URL are empty")
    }

    // MARK: - Cross-App Persistence Tests

    @MainActor
    func testConfigurationIsSharedViaAppGroups() {
        // Set configuration in app group storage
        let testKey = "shared-api-key"
        let testURL = "https://shared-worker.example.com"
        let testToken = "shared-token"

        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            userDefaults.set(testKey, forKey: "511_API_KEY")
            userDefaults.set(testURL, forKey: "WORKER_BASE_URL")
            userDefaults.set(testToken, forKey: "WORKER_TOKEN")
        }

        // ConfigurationManager should read these values
        let manager = ConfigurationManager.shared
        XCTAssertEqual(manager.apiKey, testKey,
                       "ConfigurationManager should read API key from app groups")
        XCTAssertEqual(manager.workerBaseURL, testURL,
                       "ConfigurationManager should read worker URL from app groups")
        XCTAssertEqual(manager.workerToken, testToken,
                       "ConfigurationManager should read worker token from app groups")
    }

    @MainActor
    func testEmptyStringsWhenNotSet() {
        // Ensure nothing is set
        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            userDefaults.removeObject(forKey: "511_API_KEY")
            userDefaults.removeObject(forKey: "WORKER_TOKEN")
            userDefaults.removeObject(forKey: "WORKER_BASE_URL")
        }

        let manager = ConfigurationManager.shared
        XCTAssertEqual(manager.apiKey, "",
                       "apiKey should be empty string when not set")
        XCTAssertEqual(manager.workerToken, "",
                       "workerToken should be empty string when not set")
        XCTAssertEqual(manager.workerBaseURL, "",
                       "workerBaseURL should be empty string when not set")
    }

    // MARK: - Update and Overwrite Tests

    @MainActor
    func testOverwritingAPIKey() {
        ConfigurationManager.shared.apiKey = "first-key"
        ConfigurationManager.shared.apiKey = "second-key"

        XCTAssertEqual(ConfigurationManager.shared.apiKey, "second-key",
                       "Should overwrite API key with new value")

        if let userDefaults = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName) {
            XCTAssertEqual(userDefaults.string(forKey: "511_API_KEY"), "second-key",
                           "App group storage should have the updated value")
        }
    }

    @MainActor
    func testUpdatingWorkerConfiguration() {
        // Set initial config
        ConfigurationManager.shared.setWorkerConfig(
            url: "https://initial.example.com",
            token: "initial-token"
        )

        // Update with new config
        ConfigurationManager.shared.setWorkerConfig(
            url: "https://updated.example.com",
            token: "updated-token"
        )

        XCTAssertEqual(ConfigurationManager.shared.workerBaseURL, "https://updated.example.com")
        XCTAssertEqual(ConfigurationManager.shared.workerToken, "updated-token")
    }
}
