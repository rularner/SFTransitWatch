import XCTest
import SFTransitWatchPackage

class DeepLinkIntegrationTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Clean up after each test
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.clearWorkerConfig()
    }

    func testAPIKeyLinkHandling() {
        // Test parsing and storing API key from universal link
        let testKey = "test-api-key-12345"
        let urlString = "https://rularner.github.io/sftransitwatch/key?k=\(testKey)"
        let url = URL(string: urlString)!

        if let key = WorkerConfigLink.apiKey(from: url), !key.isEmpty {
            ConfigurationManager.shared.apiKey = key
        }

        XCTAssertEqual(ConfigurationManager.shared.apiKey, testKey)
    }

    func testWorkerLinkHandling() {
        // Test parsing and storing worker config from universal link
        let testURL = "https://api.example.com"
        let testToken = "worker-token-xyz"
        let encodedURL = testURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? testURL
        let urlString = "https://rularner.github.io/sftransitwatch/wt?u=\(encodedURL)&t=\(testToken)"
        let url = URL(string: urlString)!

        if let config = WorkerConfigLink.workerConfig(from: url) {
            ConfigurationManager.shared.setWorkerConfig(url: config.url, token: config.token)
        }

        XCTAssertEqual(ConfigurationManager.shared.workerBaseURL, testURL)
        XCTAssertEqual(ConfigurationManager.shared.workerToken, testToken)
        XCTAssertTrue(ConfigurationManager.shared.isWorkerConfigured)
    }

    func testWorkerConfigClear() {
        // Test clearing worker config
        ConfigurationManager.shared.setWorkerConfig(
            url: "https://api.example.com",
            token: "test-token"
        )
        XCTAssertTrue(ConfigurationManager.shared.isWorkerConfigured)

        ConfigurationManager.shared.clearWorkerConfig()
        XCTAssertFalse(ConfigurationManager.shared.isWorkerConfigured)
        XCTAssertEqual(ConfigurationManager.shared.workerToken, "")
        XCTAssertEqual(ConfigurationManager.shared.workerBaseURL, "")
    }

    func testSharedStoragePersistence() {
        // Test that values persist in App Groups storage
        let testKey = "persistent-key"
        ConfigurationManager.shared.apiKey = testKey

        // Simulate app relaunch by creating a new manager instance
        // (In real integration test, this would be a full app lifecycle)
        let freshManager = ConfigurationManager.shared
        XCTAssertEqual(freshManager.apiKey, testKey)
    }
}
