import XCTest
@testable import SFTransitWatch_Watch_App

final class BusArrivalTests: XCTestCase {

    // MARK: - minutesAway

    func testMinutesAwayFiveMinutes() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(300))
        XCTAssertEqual(arrival.minutesAway, 5)
    }

    func testMinutesAwayDue() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(10))
        XCTAssertEqual(arrival.minutesAway, 0)
    }

    func testMinutesAwayNeverNegative() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(-120))
        XCTAssertGreaterThanOrEqual(arrival.minutesAway, 0)
    }

    // MARK: - minutesString

    func testMinutesStringDue() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(10))
        XCTAssertEqual(arrival.minutesString, "Due")
    }

    func testMinutesStringOneMinute() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(90))
        XCTAssertEqual(arrival.minutesString, "1 min")
    }

    func testMinutesStringMultiple() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(600))
        XCTAssertEqual(arrival.minutesString, "10 min")
    }

    // MARK: - timeString

    func testTimeStringNotEmpty() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(300))
        XCTAssertFalse(arrival.timeString.isEmpty)
    }

    // MARK: - isRealTime default

    func testDefaultIsRealTime() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(300))
        XCTAssertTrue(arrival.isRealTime)
    }

    func testScheduledFlag() {
        let arrival = BusArrival(route: "F", destination: "Wharf",
                                 arrivalTime: Date().addingTimeInterval(300),
                                 isRealTime: false)
        XCTAssertFalse(arrival.isRealTime)
    }
}
