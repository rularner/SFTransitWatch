import Foundation
import Testing
@testable import SFTransitWatchPackage

@Suite struct ArrivalFilterTests {
    private func arrival(route: String) -> BusArrival {
        BusArrival(route: route, destination: "Test", arrivalTime: Date().addingTimeInterval(300))
    }

    @Test func filterByNilRouteReturnsAll() {
        let arrivals = [arrival(route: "38"), arrival(route: "F")]
        #expect(arrivals.filtered(by: nil).count == 2)
    }

    @Test func filterByRouteKeepsOnlyMatches() {
        let arrivals = [arrival(route: "38"), arrival(route: "F"), arrival(route: "38")]
        let result = arrivals.filtered(by: "38")
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.route == "38" })
    }

    @Test func filterByNonexistentRouteReturnsEmpty() {
        let arrivals = [arrival(route: "38"), arrival(route: "F")]
        #expect(arrivals.filtered(by: "99").isEmpty)
    }

    @Test func uniqueRoutesIsEmptyForNoArrivals() {
        let arrivals: [BusArrival] = []
        #expect(arrivals.uniqueRoutes.isEmpty)
    }

    @Test func uniqueRoutesPreservesFirstAppearanceOrder() {
        let arrivals = [arrival(route: "38"), arrival(route: "F"), arrival(route: "38")]
        #expect(arrivals.uniqueRoutes == ["38", "F"])
    }

    @Test func uniqueRoutesDeduplicates() {
        let arrivals = [arrival(route: "N"), arrival(route: "N"), arrival(route: "J")]
        #expect(arrivals.uniqueRoutes.count == 2)
    }
}

@Suite struct EffectiveHeadingTests {
    @Test func prefersTrueHeadingWhenPositive() {
        #expect(effectiveHeadingDegrees(trueHeading: 90.0, magneticHeading: 85.0) == 90.0)
    }

    @Test func trueHeadingZeroIsValid() {
        // 0.0 = true north; ≥ 0 so trueHeading should win
        #expect(effectiveHeadingDegrees(trueHeading: 0.0, magneticHeading: 10.0) == 0.0)
    }

    @Test func fallsBackToMagneticWhenTrueIsNegative() {
        // CLHeading uses -1 when trueHeading is uncalibrated
        #expect(effectiveHeadingDegrees(trueHeading: -1.0, magneticHeading: 85.0) == 85.0)
    }

    @Test func trueHeading360IsValid() {
        #expect(effectiveHeadingDegrees(trueHeading: 360.0, magneticHeading: 10.0) == 360.0)
    }
}
