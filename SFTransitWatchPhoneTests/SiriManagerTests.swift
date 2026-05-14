import XCTest
@testable import SFTransitWatch
import SFTransitWatchPackage

final class SiriManagerTests: XCTestCase {

    func testShouldDonateNearbyStopsWithEmptyList() {
        let result = SiriManager.shouldDonateNearbyStops(stops: [])
        XCTAssertFalse(result)
    }

    func testShouldDonateNearbyStopsWithValidStops() {
        let stops = [
            BusStop(id: "1", name: "Stop 1", code: "S1", latitude: 37.7, longitude: -122.4, routes: ["1"]),
            BusStop(id: "2", name: "Stop 2", code: "S2", latitude: 37.8, longitude: -122.5, routes: ["2"])
        ]
        let result = SiriManager.shouldDonateNearbyStops(stops: stops)
        XCTAssertTrue(result)
    }

}
