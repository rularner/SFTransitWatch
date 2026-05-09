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

    func testSnapshot_BusStopList() {
        let app = launchSnapshotModeApp()
        XCTAssertTrue(app.staticTexts["Castro Station"].waitForExistence(timeout: 10),
                      "Expected Castro Station to be visible (SnapshotMode should serve it)")
        XCUISnapshotRunner.verify(named: "BusStopList", in: self)
    }

    func testSnapshot_BusArrival() {
        let app = launchSnapshotModeApp()
        let castro = app.staticTexts["Castro Station"]
        XCTAssertTrue(castro.waitForExistence(timeout: 10))
        castro.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["K"].waitForExistence(timeout: 10),
                      "Expected K-Ingleside arrival row to be visible")
        XCUISnapshotRunner.verify(named: "BusArrival", in: self)
    }

    func testSnapshot_Settings() {
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
        XCUISnapshotRunner.verify(named: "Settings", in: self)
    }

    func testSnapshot_StopCodeEntry() {
        let app = launchSnapshotModeApp()
        let searchButton = app.buttons.matching(identifier: "magnifyingglass").firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10),
                      "Search toolbar button not found — may need accessibilityIdentifier")
        searchButton.tap()
        XCTAssertTrue(app.staticTexts["Find Stop by Code"].waitForExistence(timeout: 10))
        XCUISnapshotRunner.verify(named: "StopCodeEntry", in: self)
    }
}
