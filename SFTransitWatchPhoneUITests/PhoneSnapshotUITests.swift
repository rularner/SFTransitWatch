import XCTest

final class PhoneSnapshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchSnapshotModeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-SNAPSHOT_MODE",
            "-511_API_KEY", "fake-snapshot-key",
        ]
        app.launch()
        return app
    }

    /// Regression test: tapping "Use 511.org API Key" during onboarding presents
    /// `SettingsView` from a sheet attached at the `WindowGroup` level. `SettingsView`
    /// requires `FavoritesManager`/`CommuteSlotsManager` as `@EnvironmentObject`s, which
    /// are only injected inside `ContentView` — so before the fix this path crashed with
    /// "No ObservableObject of type FavoritesManager found".
    ///
    /// Launches unconfigured (no API key / worker token) so the onboarding sheet appears.
    func testOnboarding_UseKeyButton_PresentsSettingsWithoutCrashing() throws {
        let app = XCUIApplication()
        // -SNAPSHOT_MODE stubs location; empty key/token force the unconfigured
        // (onboarding) state regardless of any persisted app-group prefs.
        app.launchArguments += [
            "-SNAPSHOT_MODE",
            "-511_API_KEY", "",
            "-WORKER_TOKEN", "",
        ]
        app.launch()

        let useKeyButton = app.buttons["Use 511.org API Key"]
        XCTAssertTrue(useKeyButton.waitForExistence(timeout: 10),
                      "Onboarding 'Use 511.org API Key' button should appear when the app is unconfigured")
        useKeyButton.tap()

        XCTAssertTrue(app.staticTexts["API Key"].waitForExistence(timeout: 10),
                      "SettingsView should present without crashing after tapping 'Use 511.org API Key'")
    }

    func testSnapshot_BusStopList() throws {
        let app = launchSnapshotModeApp()
        XCTAssertTrue(app.staticTexts["Castro Station"].waitForExistence(timeout: 10),
                      "Expected Castro Station to be visible (SnapshotMode should serve it)")
        try XCUISnapshotRunner.verify(app, named: "BusStopList", in: self, topPixelsToIgnore: 140)
    }

    func testSnapshot_BusArrival() throws {
        let app = launchSnapshotModeApp()
        let castro = app.staticTexts["Castro Station"]
        XCTAssertTrue(castro.waitForExistence(timeout: 10))
        castro.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["K"].waitForExistence(timeout: 10),
                      "Expected K-Ingleside arrival row to be visible")
        try XCUISnapshotRunner.verify(app, named: "BusArrival", in: self, topPixelsToIgnore: 140)
    }

    func testSnapshot_Settings() throws {
        let app = launchSnapshotModeApp()
        let settingsButton = app.buttons.matching(identifier: "gearshape").firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10),
                      "Settings button not found — may need accessibilityIdentifier")
        settingsButton.tap()
        XCTAssertTrue(app.staticTexts["API Key"].waitForExistence(timeout: 10),
                      "Expected Settings screen's API Key section header")
        try XCUISnapshotRunner.verify(app, named: "Settings", in: self, topPixelsToIgnore: 140)
    }

    func testSnapshot_StopSearch() throws {
        let app = launchSnapshotModeApp()
        XCTAssertTrue(app.staticTexts["Castro Station"].waitForExistence(timeout: 10),
                      "Stop list must load before tapping search")
        let searchButton = app.buttons.matching(identifier: "magnifyingglass").firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5),
                      "Search toolbar button not found")
        searchButton.tap()
        XCTAssertTrue(app.staticTexts["Find a Stop"].waitForExistence(timeout: 5),
                      "Expected 'Find a Stop' sheet title")
        try XCUISnapshotRunner.verify(app, named: "StopSearch", in: self, topPixelsToIgnore: 140)
    }

    func testSnapshot_SiriShortcuts() throws {
        let app = launchSnapshotModeApp()
        let settingsButton = app.buttons.matching(identifier: "gearshape").firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10),
                      "Settings button not found")
        settingsButton.tap()

        XCTAssertTrue(app.staticTexts["API Key"].waitForExistence(timeout: 10),
                      "Settings view not loaded")

        sleep(1)

        let settingsList = app.tables.firstMatch
        settingsList.swipeUp()

        sleep(1)

        let voiceCommandsText = app.staticTexts.matching(NSPredicate(format: "label == 'Voice Commands'")).firstMatch
        XCTAssertTrue(voiceCommandsText.waitForExistence(timeout: 10),
                      "Voice Commands text not found after scroll")

        voiceCommandsText.tap()

        XCTAssertTrue(app.navigationBars["Siri"].waitForExistence(timeout: 10),
                      "Siri Shortcuts view did not appear")
        try XCUISnapshotRunner.verify(app, named: "SiriShortcuts", in: self, topPixelsToIgnore: 140)
    }

    func testSnapshot_Paywall() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-SNAPSHOT_MODE",
            "-SNAPSHOT_PAYWALL",
            "-511_API_KEY", "",
            "-WORKER_TOKEN", "",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Subscribe"].waitForExistence(timeout: 10),
                      "Onboarding paywall Subscribe button should appear")
        XCTAssertTrue(app.staticTexts["Free for 1 week"].exists,
                      "Paywall should show the free-trial intro offer")
        try XCUISnapshotRunner.verify(app, named: "Paywall", in: self, topPixelsToIgnore: 140)
    }

}
