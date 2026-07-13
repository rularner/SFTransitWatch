import XCTest
import SFTransitWatchPackage

final class ProvisionRefreshGateTests: XCTestCase {
    func testRefreshesWhenNeverRefreshedBefore() {
        XCTAssertTrue(ProvisionRefreshGate.shouldRefresh(lastRefreshAt: nil, now: Date()))
    }

    func testDoesNotRefreshBeforeMinimumIntervalElapses() {
        let now = Date()
        let lastRefreshAt = now.addingTimeInterval(-ProvisionRefreshGate.minimumInterval + 1)
        XCTAssertFalse(ProvisionRefreshGate.shouldRefresh(lastRefreshAt: lastRefreshAt, now: now))
    }

    func testRefreshesOnceMinimumIntervalElapses() {
        let now = Date()
        let lastRefreshAt = now.addingTimeInterval(-ProvisionRefreshGate.minimumInterval)
        XCTAssertTrue(ProvisionRefreshGate.shouldRefresh(lastRefreshAt: lastRefreshAt, now: now))
    }

    /// The whole point: rapid foreground/background cycling (app switches,
    /// Face ID prompts, StoreKit sheets) must not each trigger a call.
    func testRapidForegroundingOnlyRefreshesOnce() {
        let start = Date()
        var lastRefreshAt: Date?
        var refreshes = 0
        for minute in 0..<30 {
            let now = start.addingTimeInterval(TimeInterval(minute * 60))
            if ProvisionRefreshGate.shouldRefresh(lastRefreshAt: lastRefreshAt, now: now) {
                refreshes += 1
                lastRefreshAt = now
            }
        }
        XCTAssertEqual(refreshes, 1)
    }
}
