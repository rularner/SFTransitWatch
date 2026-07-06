import XCTest
import SFTransitWatchPackage

@MainActor
final class RefreshCountdownTests: XCTestCase {
    func testStartsAtInterval() {
        let countdown = RefreshCountdown(interval: 30)
        XCTAssertEqual(countdown.secondsRemaining, 30)
    }

    func testTickDecrementsWhenAboveOne() {
        let countdown = RefreshCountdown(interval: 30)
        let shouldRefresh = countdown.tick()
        XCTAssertEqual(countdown.secondsRemaining, 29)
        XCTAssertFalse(shouldRefresh)
    }

    func testTickAtOneWrapsAndSignalsRefresh() {
        let countdown = RefreshCountdown(interval: 3)
        _ = countdown.tick() // 3 -> 2
        _ = countdown.tick() // 2 -> 1
        let shouldRefresh = countdown.tick() // 1 -> wrap to 3, fire
        XCTAssertTrue(shouldRefresh)
        XCTAssertEqual(countdown.secondsRemaining, 3)
    }

    func testResetRestoresInterval() {
        let countdown = RefreshCountdown(interval: 30)
        _ = countdown.tick()
        _ = countdown.tick()
        countdown.reset()
        XCTAssertEqual(countdown.secondsRemaining, 30)
    }

    func testSetIntervalChangesNextWrap() {
        let countdown = RefreshCountdown(interval: 30)
        countdown.setInterval(10)
        XCTAssertEqual(countdown.interval, 10)
        // Count down from the (clamped) remaining to the new wrap.
        var refreshes = 0
        for _ in 0..<10 { if countdown.tick() { refreshes += 1 } }
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(countdown.secondsRemaining, 10)
    }

    func testSetSmallerIntervalClampsRemaining() {
        let countdown = RefreshCountdown(interval: 120)
        XCTAssertEqual(countdown.secondsRemaining, 120)
        countdown.setInterval(30)
        // Should not keep waiting the old, longer time.
        XCTAssertEqual(countdown.secondsRemaining, 30)
    }

    func testSetLargerIntervalKeepsCurrentRemaining() {
        let countdown = RefreshCountdown(interval: 30)
        _ = countdown.tick() // 30 -> 29
        countdown.setInterval(60)
        XCTAssertEqual(countdown.secondsRemaining, 29)
    }

    func testSetSameIntervalIsNoOp() {
        let countdown = RefreshCountdown(interval: 30)
        _ = countdown.tick() // 30 -> 29
        countdown.setInterval(30)
        XCTAssertEqual(countdown.secondsRemaining, 29)
    }

    /// The whole point of the workstream: one refresh per interval, never two.
    func testFiresExactlyOncePerInterval() {
        let interval = 30
        let countdown = RefreshCountdown(interval: interval)
        var refreshes = 0
        // Simulate three full intervals of one-second ticks.
        for _ in 0..<(interval * 3) {
            if countdown.tick() { refreshes += 1 }
        }
        XCTAssertEqual(refreshes, 3)
    }
}
