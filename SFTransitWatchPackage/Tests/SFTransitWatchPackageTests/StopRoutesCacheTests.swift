import Foundation
import Testing
@testable import SFTransitWatchPackage

@Suite struct StopRoutesCacheTests {
    private func makeCache() -> StopRoutesCache {
        let suite = "StopRoutesCacheTests-\(UUID().uuidString)"
        return StopRoutesCache(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func missingEntryReturnsNil() {
        let cache = makeCache()
        #expect(cache.routes(for: "1234", agency: "SF") == nil)
    }

    @Test func freshEntryReturnsCachedRoutes() {
        let cache = makeCache()
        cache.setRoutes(["38", "38R"], for: "1234", agency: "SF", now: Date())
        #expect(cache.routes(for: "1234", agency: "SF", now: Date()) == ["38", "38R"])
    }

    @Test func entryOlderThanSevenDaysReturnsNil() {
        let cache = makeCache()
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        cache.setRoutes(["38"], for: "1234", agency: "SF", now: eightDaysAgo)
        #expect(cache.routes(for: "1234", agency: "SF", now: Date()) == nil)
    }

    @Test func entryExactlyWithinSevenDaysReturnsRoutes() {
        let cache = makeCache()
        let sixDaysAgo = Date().addingTimeInterval(-6 * 24 * 60 * 60)
        cache.setRoutes(["38"], for: "1234", agency: "SF", now: sixDaysAgo)
        #expect(cache.routes(for: "1234", agency: "SF", now: Date()) == ["38"])
    }

    @Test func emptyRoutesAreCachedAndReturnedAsEmptyNotNil() {
        let cache = makeCache()
        cache.setRoutes([], for: "1234", agency: "SF", now: Date())
        #expect(cache.routes(for: "1234", agency: "SF", now: Date()) == [])
    }

    @Test func entriesAreScopedByAgencyAndStopId() {
        let cache = makeCache()
        cache.setRoutes(["38"], for: "1234", agency: "SF", now: Date())
        cache.setRoutes(["F"], for: "1234", agency: "CT", now: Date())
        #expect(cache.routes(for: "1234", agency: "SF") == ["38"])
        #expect(cache.routes(for: "1234", agency: "CT") == ["F"])
    }
}
