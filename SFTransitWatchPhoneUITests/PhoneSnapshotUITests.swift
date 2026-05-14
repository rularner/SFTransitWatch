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

}
