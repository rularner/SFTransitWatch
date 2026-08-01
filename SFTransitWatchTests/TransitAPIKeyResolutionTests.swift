import XCTest
import SFTransitWatchPackage
@testable import SFTransitWatch_Watch_App

/// Regression test for the dual API-key-store bug: a stale phone-synced key
/// must never outrank a key set (or cleared) directly via watch Settings.
final class TransitAPIKeyResolutionTests: XCTestCase {

    var api: TransitAPI!
    var mockSession: MockURLSession!

    @MainActor
    override func setUp() {
        super.setUp()
        api = TransitAPI()
        mockSession = MockURLSession()
        api.urlSession = mockSession
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.workerToken = ""
        ConfigurationManager.shared.workerBaseURL = ""
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
    }

    @MainActor
    override func tearDown() {
        super.tearDown()
        ConfigurationManager.shared.apiKey = ""
        UserDefaults.standard.removeObject(forKey: "511_API_KEY_FROM_PHONE")
    }

    /// Simulates: phone sync once populated the legacy `.standard` copy, then
    /// the user set a fresh key directly in watch Settings (which only ever
    /// writes ConfigurationManager.shared.apiKey). The request must carry the
    /// Settings-set key, not the stale phone-synced one.
    @MainActor
    func testWatchSettingsKeyWinsOverStalePhoneSyncedKey() async {
        UserDefaults.standard.set("stale-phone-key", forKey: "511_API_KEY_FROM_PHONE")
        ConfigurationManager.shared.apiKey = "new-watch-settings-key"

        _ = await api.fetchArrivals(for: "12345", agency: "SF")

        let request = mockSession.lastRequest()
        let components = request.flatMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false) }
        let apiKeyParam = components?.queryItems?.first { $0.name == "api_key" }?.value
        XCTAssertEqual(apiKeyParam, "new-watch-settings-key")
    }
}
