import XCTest

final class WatchSnapshotUITests: XCTestCase {

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
        try XCUISnapshotRunner.verify(app, named: "BusStopList", in: self, topPixelsToIgnore: 200)
    }

    func testSnapshot_BusArrival() throws {
        let app = launchSnapshotModeApp()
        let castro = app.staticTexts["Castro Station"]
        XCTAssertTrue(castro.waitForExistence(timeout: 10))
        castro.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["K"].waitForExistence(timeout: 10),
                      "Expected K-Ingleside arrival row to be visible")
        try XCUISnapshotRunner.verify(app, named: "BusArrival", in: self, topPixelsToIgnore: 200)
    }

    func testSnapshot_Settings() throws {
        let app = launchSnapshotModeApp()
        // Toolbar gear icon. If `app.buttons["gearshape"]` doesn't match, the view may need
        // an explicit `.accessibilityIdentifier("Settings")` modifier in BusStopListView.swift
        // or ContentView.swift — surface as a follow-up if so.
        let settingsButton = app.buttons.matching(identifier: "gearshape").firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10),
                      "Settings toolbar button not found — may need accessibilityIdentifier")
        settingsButton.tap()
        XCTAssertTrue(app.staticTexts["API Key"].waitForExistence(timeout: 10),
                      "Expected Settings screen's API Key section header")
        try XCUISnapshotRunner.verify(app, named: "Settings", in: self, topPixelsToIgnore: 200)
    }

    func testSnapshot_StopCodeEntry() throws {
        let app = launchSnapshotModeApp()
        let searchButton = app.buttons.matching(identifier: "magnifyingglass").firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10),
                      "Search toolbar button not found — may need accessibilityIdentifier")
        searchButton.tap()
        XCTAssertTrue(app.staticTexts["Find Stop by Code"].waitForExistence(timeout: 10))
        try XCUISnapshotRunner.verify(app, named: "StopCodeEntry", in: self, topPixelsToIgnore: 200)
    }
}
