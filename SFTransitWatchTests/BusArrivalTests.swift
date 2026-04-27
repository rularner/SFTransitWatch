import XCTest
@testable import SFTransitWatch_Watch_App

final class BusArrivalTests: XCTestCase {

    // MARK: - minutesAway

    func testMinutesAwayFiveMinutes() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(300),
                                 now: now)
        XCTAssertEqual(arrival.minutesAway, 5)
    }

    func testMinutesAwayDue() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(10),
                                 now: now)
        XCTAssertEqual(arrival.minutesAway, 0)
    }

    func testMinutesAwayNeverNegative() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(-120),
                                 now: now)
        XCTAssertGreaterThanOrEqual(arrival.minutesAway, 0)
    }

    // MARK: - minutesString

    func testMinutesStringDue() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(10),
                                 now: now)
        XCTAssertEqual(arrival.minutesString, "Due")
    }

    func testMinutesStringOneMinute() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(90),
                                 now: now)
        XCTAssertEqual(arrival.minutesString, "1 min")
    }

    func testMinutesStringMultiple() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(600),
                                 now: now)
        XCTAssertEqual(arrival.minutesString, "10 min")
    }

    // MARK: - timeString

    func testTimeStringNotEmpty() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(300),
                                 now: now)
        XCTAssertFalse(arrival.timeString.isEmpty)
    }

    // MARK: - isRealTime default

    func testDefaultIsRealTime() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(300),
                                 now: now)
        XCTAssertTrue(arrival.isRealTime)
    }

    func testScheduledFlag() {
        let now = Date()
        let arrival = BusArrival(route: "F", destination: "Wharf",
                                 arrivalTime: now.addingTimeInterval(300),
                                 isRealTime: false,
                                 now: now)
        XCTAssertFalse(arrival.isRealTime)
    }

    // Regression guard: if BusArrival.init ever stops honoring the injected
    // `now` (e.g. someone reverts to `arrivalTime.timeIntervalSinceNow`), the
    // calculation will be made against the real wall clock — which is decades
    // away from this fixed reference date — and these assertions will fail.
    func testInjectedNowIsRespected() {
        let frozen = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01 UTC
        let fiveMinLater = BusArrival(route: "X", destination: "Y",
                                      arrivalTime: frozen.addingTimeInterval(300),
                                      now: frozen)
        XCTAssertEqual(fiveMinLater.minutesAway, 5)

        let twoMinEarlier = BusArrival(route: "X", destination: "Y",
                                       arrivalTime: frozen.addingTimeInterval(-120),
                                       now: frozen)
        XCTAssertEqual(twoMinEarlier.minutesAway, 0)
    }
}
