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

    func testSnapshot_BusStopList() {
        let app = launchSnapshotModeApp()
        XCTAssertTrue(app.staticTexts["Castro Station"].waitForExistence(timeout: 10),
                      "Expected Castro Station to be visible (SnapshotMode should serve it)")
        XCUISnapshotRunner.verify(app, named: "BusStopList", in: self, topPixelsToIgnore: 140)
    }

    func testSnapshot_BusArrival() {
        let app = launchSnapshotModeApp()
        let castro = app.staticTexts["Castro Station"]
        XCTAssertTrue(castro.waitForExistence(timeout: 10))
        castro.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["K"].waitForExistence(timeout: 10),
                      "Expected K-Ingleside arrival row to be visible")
        XCUISnapshotRunner.verify(app, named: "BusArrival", in: self, topPixelsToIgnore: 140)
    }

    func testSnapshot_Settings() {
        let app = launchSnapshotModeApp()
        let settingsButton = app.buttons.matching(identifier: "gearshape").firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10),
                      "Settings button not found — may need accessibilityIdentifier")
        settingsButton.tap()
        XCTAssertTrue(app.staticTexts["API Key"].waitForExistence(timeout: 10),
                      "Expected Settings screen's API Key section header")
        XCUISnapshotRunner.verify(app, named: "Settings", in: self, topPixelsToIgnore: 140)
    }

    func testSnapshot_SiriShortcuts() {
        let app = launchSnapshotModeApp()
        let settingsButton = app.buttons.matching(identifier: "gearshape").firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let siriLink = app.staticTexts.matching(identifier: "Siri Shortcuts").firstMatch
        XCTAssertTrue(siriLink.waitForExistence(timeout: 10))
        siriLink.tap()

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Siri'")).firstMatch.waitForExistence(timeout: 10),
                      "Siri Shortcuts view did not appear")
        XCUISnapshotRunner.verify(app, named: "SiriShortcuts", in: self, topPixelsToIgnore: 140)
    }

}
