import XCTest
@testable import SFTransitWatchPackage

/// Basic coverage that outbound requests carry the currently configured API key.
///
/// This was originally `testWatchSettingsKeyWinsOverStalePhoneSyncedKey`, a regression
/// test for a dual API-key-store bug: a stale phone-synced UserDefaults value
/// (`"511_API_KEY_FROM_PHONE"`) could outrank a key set (or cleared) directly via watch
/// Settings. Task 1's `TransitAPI` merge removed the vulnerable code path entirely rather
/// than fixing it conditionally — the merged class only ever reads
/// `ConfigurationManager.shared.apiKey`; no other API-key store is consulted anywhere in
/// the class. The dual-store bug is therefore now structurally impossible, not merely
/// guarded against by a test. What's left worth keeping is the underlying basic
/// assertion: a request carries the currently-configured key.
@MainActor
final class TransitAPIKeyResolutionTests: XCTestCase {

    var api: TransitAPI!
    var mockSession: MockURLSession!

    override func setUp() async throws {
        try await super.setUp()
        api = TransitAPI()
        mockSession = MockURLSession()
        api.urlSession = mockSession
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.workerToken = ""
        ConfigurationManager.shared.workerBaseURL = ""
    }

    override func tearDown() async throws {
        try await super.tearDown()
        ConfigurationManager.shared.apiKey = ""
    }

    func testRequestCarriesConfiguredAPIKey() async {
        ConfigurationManager.shared.apiKey = "new-watch-settings-key"

        _ = await api.fetchArrivals(for: "12345", agency: "SF")

        let request = mockSession.lastRequest()
        let components = request.flatMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false) }
        let apiKeyParam = components?.queryItems?.first { $0.name == "api_key" }?.value
        XCTAssertEqual(apiKeyParam, "new-watch-settings-key")
    }
}
