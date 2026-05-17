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

    /// Launches directly into BusArrivalView (arrivals tab) for Castro Station,
    /// bypassing the stop list. watchOS List cells aren't reliably queryable via XCUI.
    private func launchSnapshotModeAppAtArrival() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-SNAPSHOT_MODE",
            "-SNAPSHOT_ARRIVAL",
            "-511_API_KEY", "fake-snapshot-key",
        ]
        app.launch()
        return app
    }

    /// Launches directly into BusArrivalView on the location/compass tab (tab 1).
    private func launchSnapshotModeAppAtLocation() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-SNAPSHOT_MODE",
            "-SNAPSHOT_LOCATION",
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
        let app = launchSnapshotModeAppAtArrival()
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
        let app = launchSnapshotModeAppAtLocation()
        XCTAssertTrue(app.staticTexts["Distance"].waitForExistence(timeout: 10),
                      "Expected Distance label in StopLocationView compass tab")
        try XCUISnapshotRunner.verify(app, named: "StopLocation", in: self, topPixelsToIgnore: 200)
    }
}
