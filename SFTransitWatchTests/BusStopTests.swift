import XCTest
import CoreLocation
@testable import SFTransitWatch_Watch_App

final class BusStopTests: XCTestCase {

    private let marketAndFourth = BusStop(
        id: "1",
        name: "Market St & 4th St",
        code: "M4",
        latitude: 37.7858,
        longitude: -122.4064,
        routes: ["38", "38R", "F"]
    )

    // MARK: - distance

    func testDistanceToSameLocationIsZero() {
        let here = CLLocation(latitude: 37.7858, longitude: -122.4064)
        XCTAssertEqual(marketAndFourth.distance(to: here), 0, accuracy: 1)
    }

    func testDistanceToNearbyLocationIsPositive() {
        let nearby = CLLocation(latitude: 37.7900, longitude: -122.4100)
        XCTAssertGreaterThan(marketAndFourth.distance(to: nearby), 0)
    }

    func testDistanceIsApproximatelyCorrect() {
        // ~500 m north
        let north = CLLocation(latitude: 37.7903, longitude: -122.4064)
        let distance = marketAndFourth.distance(to: north)
        XCTAssertGreaterThan(distance, 400)
        XCTAssertLessThan(distance, 600)
    }

    // MARK: - coordinate / location

    func testCoordinateMatchesInit() {
        XCTAssertEqual(marketAndFourth.coordinate.latitude, 37.7858, accuracy: 0.0001)
        XCTAssertEqual(marketAndFourth.coordinate.longitude, -122.4064, accuracy: 0.0001)
    }

    // MARK: - isFavorite default

    func testIsFavoriteDefaultFalse() {
        let stop = BusStop(id: "x", name: "Test", code: "T1", latitude: 0, longitude: 0)
        XCTAssertFalse(stop.isFavorite)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(marketAndFourth)
        let decoded = try JSONDecoder().decode(BusStop.self, from: data)
        XCTAssertEqual(decoded.id, marketAndFourth.id)
        XCTAssertEqual(decoded.name, marketAndFourth.name)
        XCTAssertEqual(decoded.routes, marketAndFourth.routes)
        XCTAssertEqual(decoded.latitude, marketAndFourth.latitude)
        XCTAssertEqual(decoded.agency, "SF")
    }

    // MARK: - agency

    func testAgencyDefaultsToMuniWhenOmitted() {
        let stop = BusStop(id: "x", name: "T", code: "T1", latitude: 0, longitude: 0)
        XCTAssertEqual(stop.agency, "SF")
    }

    func testAgencyExplicit() {
        let stop = BusStop(id: "x", name: "T", code: "T1", latitude: 0, longitude: 0, agency: "BA")
        XCTAssertEqual(stop.agency, "BA")
    }

    /// Pinned/favorite stops persisted before agency was introduced lack the
    /// `agency` field. Decoding must default them to "SF" rather than fail.
    func testDecodingLegacyJSONDefaultsAgencyToMuni() throws {
        let json = """
        {"id":"1","name":"X","code":"X1","latitude":1.0,"longitude":2.0,"routes":[],"isFavorite":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BusStop.self, from: json)
        XCTAssertEqual(decoded.agency, "SF")
    }

    func testCodableRoundTripPreservesAgency() throws {
        let bart = BusStop(id: "9", name: "Embarcadero", code: "EMB", latitude: 37.793, longitude: -122.397, agency: "BA")
        let data = try JSONEncoder().encode(bart)
        let decoded = try JSONDecoder().decode(BusStop.self, from: data)
        XCTAssertEqual(decoded.agency, "BA")
    }
}
