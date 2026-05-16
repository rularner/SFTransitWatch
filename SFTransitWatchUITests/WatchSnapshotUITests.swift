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
        // BusStopRow uses accessibilityElement(children: .combine), so individual
        // staticTexts are hidden. The section header is always a plain staticText.
        XCTAssertTrue(app.staticTexts["Nearby Stops"].waitForExistence(timeout: 10),
                      "Expected Nearby Stops section header (SnapshotMode should serve stops)")
        try XCUISnapshotRunner.verify(app, named: "BusStopList", in: self, topPixelsToIgnore: 200)
    }

    func testSnapshot_BusArrival() throws {
        let app = launchSnapshotModeApp()
        // BusStopRow uses accessibilityElement(children: .combine). On watchOS the
        // NavigationLink row may not be classified as a .button, so search all types.
        let castro = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Castro Station'"))
            .firstMatch
        XCTAssertTrue(castro.waitForExistence(timeout: 10),
                      "Expected Castro Station cell (SnapshotMode should serve it)")
        castro.tap()
        // "Next Arrivals" is the section header — always visible, not inside combine.
        XCTAssertTrue(app.staticTexts["Next Arrivals"].waitForExistence(timeout: 10),
                      "Expected Next Arrivals section header in BusArrivalView")
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

    func testSnapshot_StopLocation() throws {
        let app = launchSnapshotModeApp()
        let castro = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Castro Station'"))
            .firstMatch
        XCTAssertTrue(castro.waitForExistence(timeout: 10),
                      "Expected Castro Station cell (SnapshotMode should serve it)")
        castro.tap()
        XCTAssertTrue(app.staticTexts["Next Arrivals"].waitForExistence(timeout: 10),
                      "Expected Next Arrivals section header in BusArrivalView")
        // Navigate to the compass/location tab (tab 1).
        // app.swipeLeft() can trigger the watchOS back gesture or get consumed by the
        // List scroll view. An explicit coordinate drag is more reliable.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["Stop Location"].waitForExistence(timeout: 10),
                      "Expected Stop Location heading on the direction tab")
        try XCUISnapshotRunner.verify(app, named: "StopLocation", in: self, topPixelsToIgnore: 200)
    }
}
