import XCTest
import SFTransitWatchPackage

@MainActor
class DeepLinkIntegrationTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.clearWorkerConfig()
    }

    func testAPIKeyLinkHandling() {
        let testKey = "test-api-key-12345"
        let urlString = "sftransitwatch://key/\(testKey)"
        let url = URL(string: urlString)!

        if let key = WorkerConfigLink.apiKey(from: url), !key.isEmpty {
            ConfigurationManager.shared.apiKey = key
        }

        XCTAssertEqual(ConfigurationManager.shared.apiKey, testKey)
    }

    func testWorkerBootstrapLinkHandling() {
        let testURL = "https://api.example.com"
        let testCode = "one-time-bootstrap-code-xyz"
        let encodedURL = testURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? testURL
        let urlString = "sftransitwatch://wt?u=\(encodedURL)&c=\(testCode)"
        let url = URL(string: urlString)!

        if let bootstrap = WorkerConfigLink.workerBootstrap(from: url) {
            XCTAssertEqual(bootstrap.url, testURL)
            XCTAssertEqual(bootstrap.code, testCode)
        } else {
            XCTFail("Failed to parse bootstrap link")
        }
    }

    func testWorkerBootstrapLinkValidation() {
        let validURL = "https://api.example.com"
        let encodedURL = validURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? validURL
        let urlString = "sftransitwatch://wt?u=\(encodedURL)&c=code123"
        let url = URL(string: urlString)!

        XCTAssertNotNil(WorkerConfigLink.workerBootstrap(from: url))
    }

    func testWorkerBootstrapLinkRejectsNonHTTPS() {
        let invalidURL = "http://api.example.com"
        let encodedURL = invalidURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? invalidURL
        let urlString = "sftransitwatch://wt?u=\(encodedURL)&c=code123"
        let url = URL(string: urlString)!

        XCTAssertNil(WorkerConfigLink.workerBootstrap(from: url))
    }

    func testWorkerBootstrapLinkRejectsMissingParameters() {
        let urlString = "sftransitwatch://wt?u=https://api.example.com"
        let url = URL(string: urlString)!

        XCTAssertNil(WorkerConfigLink.workerBootstrap(from: url))
    }

    func testWorkerConfigClear() {
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
        let testKey = "persistent-key"
        ConfigurationManager.shared.apiKey = testKey

        let freshManager = ConfigurationManager.shared
        XCTAssertEqual(freshManager.apiKey, testKey)
    }
}
