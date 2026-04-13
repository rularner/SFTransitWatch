import XCTest
@testable import SFTransitWatch_Watch_App

@MainActor
final class AppIntentsTests: XCTestCase {

    // MARK: - CheckNearbyStopsIntent

    func testNearbyStopsIntentPerformSucceeds() async throws {
        let intent = CheckNearbyStopsIntent()
        // perform() should not throw — it just opens the app
        let _ = try await intent.perform()
    }

    // MARK: - CheckStopArrivalsIntent

    func testStopArrivalsIntentNoAPIKeyReturnsDialog() async throws {
        // Clear any stored key so we get the "not configured" path
        UserDefaults.standard.removeObject(forKey: "511_API_KEY")

        let intent = CheckStopArrivalsIntent()
        intent.stopName = "Market & 4th"
        let result = try await intent.perform()
        let dialog = result.dialog
        XCTAssertNotNil(dialog)
        // Should mention settings or API key
        let dialogText = dialog?.description ?? ""
        XCTAssertTrue(
            dialogText.localizedCaseInsensitiveContains("key") ||
            dialogText.localizedCaseInsensitiveContains("settings"),
            "Dialog should mention API key or settings, got: \(dialogText)"
        )
    }

    func testStopArrivalsIntentWithStopNameMentionsStop() async throws {
        // Provide a fake key so we hit the "opening" path
        UserDefaults.standard.set("fake-test-key", forKey: "511_API_KEY")
        defer { UserDefaults.standard.removeObject(forKey: "511_API_KEY") }

        let intent = CheckStopArrivalsIntent()
        intent.stopName = "Market & 4th"
        let result = try await intent.perform()
        let dialog = result.dialog
        let text = dialog?.description ?? ""
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("Market"),
            "Dialog should mention the stop name, got: \(text)"
        )
    }

    func testStopArrivalsIntentWithoutStopNameSucceeds() async throws {
        UserDefaults.standard.set("fake-test-key", forKey: "511_API_KEY")
        defer { UserDefaults.standard.removeObject(forKey: "511_API_KEY") }

        let intent = CheckStopArrivalsIntent()
        intent.stopName = nil
        let _ = try await intent.perform()
    }
}
