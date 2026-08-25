import Foundation
import Testing
@testable import SFTransitWatchPackage

@Suite struct ComplicationSnapshotTests {
    @Test func noExistingSnapshot_isChanged() {
        #expect(ComplicationSnapshot.hasChanged(
            existingRoute: nil,
            existingArrivalTime: nil,
            newRoute: "36",
            newArrivalTime: Date()
        ))
    }

    @Test func sameRouteAndArrivalTime_isUnchanged() {
        let time = Date()
        #expect(!ComplicationSnapshot.hasChanged(
            existingRoute: "36",
            existingArrivalTime: time,
            newRoute: "36",
            newArrivalTime: time
        ))
    }

    @Test func differentRoute_isChanged() {
        let time = Date()
        #expect(ComplicationSnapshot.hasChanged(
            existingRoute: "36",
            existingArrivalTime: time,
            newRoute: "38",
            newArrivalTime: time
        ))
    }

    @Test func differentArrivalTime_isChanged() {
        let time = Date()
        #expect(ComplicationSnapshot.hasChanged(
            existingRoute: "36",
            existingArrivalTime: time,
            newRoute: "36",
            newArrivalTime: time.addingTimeInterval(60)
        ))
    }
}
