import Testing
import Foundation
import SFTransitWatchPackage

@Suite struct AlertSettingsManagerTests {
    @MainActor
    private func makeManager() -> AlertSettingsManager {
        AlertSettingsManager(userDefaultsSuiteName: "test.alert.\(UUID().uuidString)")
    }

    // MARK: - Defaults

    @Test @MainActor
    func alertsEnabledDefaultsToTrue() {
        #expect(makeManager().alertsEnabled == true)
    }

    @Test @MainActor
    func travelMinutesDefaultsToZero() {
        let m = makeManager()
        #expect(m.travelMinutes(for: .morning) == 0)
        #expect(m.travelMinutes(for: .afternoon) == 0)
    }

    @Test @MainActor
    func windowDefaultCoversFullDay() {
        let m = makeManager()
        #expect(m.isWithinWindow(for: .morning, at: Date()))
        #expect(m.isWithinWindow(for: .afternoon, at: Date()))
    }

    @Test @MainActor
    func atStopSuppressionDefaultsToFalse() {
        let m = makeManager()
        #expect(!m.isAtStopSuppressed(for: .morning))
        #expect(!m.isAtStopSuppressed(for: .afternoon))
    }

    // MARK: - Travel time

    @Test @MainActor
    func setTravelMinutesPersists() {
        let m = makeManager()
        m.setTravelMinutes(30, for: .morning)
        m.setTravelMinutes(15, for: .afternoon)
        #expect(m.travelMinutes(for: .morning) == 30)
        #expect(m.travelMinutes(for: .afternoon) == 15)
    }

    // MARK: - isWithinWindow

    @Test @MainActor
    func isWithinWindow_beforeStart_returnsFalse() {
        let m = makeManager()
        var start = DateComponents(); start.hour = 7; start.minute = 0
        var end = DateComponents(); end.hour = 9; end.minute = 0
        m.setWindowStart(start, for: .morning)
        m.setWindowEnd(end, for: .morning)
        let date = Calendar.current.date(bySettingHour: 6, minute: 59, second: 0, of: .now)!
        #expect(!m.isWithinWindow(for: .morning, at: date))
    }

    @Test @MainActor
    func isWithinWindow_atStart_returnsTrue() {
        let m = makeManager()
        var start = DateComponents(); start.hour = 7; start.minute = 0
        var end = DateComponents(); end.hour = 9; end.minute = 0
        m.setWindowStart(start, for: .morning)
        m.setWindowEnd(end, for: .morning)
        let date = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        #expect(m.isWithinWindow(for: .morning, at: date))
    }

    @Test @MainActor
    func isWithinWindow_atEnd_returnsTrue() {
        let m = makeManager()
        var start = DateComponents(); start.hour = 7; start.minute = 0
        var end = DateComponents(); end.hour = 9; end.minute = 0
        m.setWindowStart(start, for: .morning)
        m.setWindowEnd(end, for: .morning)
        let date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        #expect(m.isWithinWindow(for: .morning, at: date))
    }

    @Test @MainActor
    func isWithinWindow_afterEnd_returnsFalse() {
        let m = makeManager()
        var start = DateComponents(); start.hour = 7; start.minute = 0
        var end = DateComponents(); end.hour = 9; end.minute = 0
        m.setWindowStart(start, for: .morning)
        m.setWindowEnd(end, for: .morning)
        let date = Calendar.current.date(bySettingHour: 9, minute: 1, second: 0, of: .now)!
        #expect(!m.isWithinWindow(for: .morning, at: date))
    }

    @Test @MainActor
    func setWindowStart_clampsEndIfStartMovedPastIt() {
        let m = makeManager()
        var start = DateComponents(); start.hour = 7; start.minute = 0
        var end = DateComponents(); end.hour = 9; end.minute = 0
        m.setWindowStart(start, for: .morning)
        m.setWindowEnd(end, for: .morning)
        // Move start past current end
        var veryLate = DateComponents(); veryLate.hour = 10; veryLate.minute = 0
        m.setWindowStart(veryLate, for: .morning)
        let newEnd = m.windowEnd(for: .morning)
        #expect((newEnd.hour ?? 0) * 60 + (newEnd.minute ?? 0) >= 10 * 60)
    }

    @Test @MainActor
    func setWindowEnd_clampsToStartIfSetBefore() {
        let m = makeManager()
        var start = DateComponents(); start.hour = 8; start.minute = 0
        m.setWindowStart(start, for: .morning)
        // Try to set end before start
        var tooEarly = DateComponents(); tooEarly.hour = 7; tooEarly.minute = 0
        m.setWindowEnd(tooEarly, for: .morning)
        let newEnd = m.windowEnd(for: .morning)
        #expect((newEnd.hour ?? 0) * 60 + (newEnd.minute ?? 0) >= 8 * 60)
    }

    // MARK: - At-stop suppression

    @Test @MainActor
    func suppressAtStop_marksAsSuppressedToday() {
        let m = makeManager()
        m.suppressAtStop(for: .morning)
        #expect(m.isAtStopSuppressed(for: .morning))
    }

    @Test @MainActor
    func suppressAtStop_doesNotAffectOtherSlot() {
        let m = makeManager()
        m.suppressAtStop(for: .morning)
        #expect(!m.isAtStopSuppressed(for: .afternoon))
    }

    @Test @MainActor
    func clearAtStopSuppression_removesSuppression() {
        let m = makeManager()
        m.suppressAtStop(for: .morning)
        m.clearAtStopSuppression(for: .morning)
        #expect(!m.isAtStopSuppressed(for: .morning))
    }

    @Test @MainActor
    func suppressionDoesNotApplyYesterday() {
        let m = makeManager()
        m.suppressAtStop(for: .morning)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        #expect(!m.isAtStopSuppressed(for: .morning, at: yesterday))
    }

    // MARK: - qualifyingArrival

    @Test @MainActor
    func qualifyingArrival_alertsDisabled_returnsNil() {
        let m = makeManager()
        m.alertsEnabled = false
        let now = Date()
        let arrivals = [BusArrival(route: "38", destination: "Downtown",
                                   arrivalTime: now.addingTimeInterval(2 * 60), now: now)]
        #expect(m.qualifyingArrival(from: arrivals, for: .morning) == nil)
    }

    @Test @MainActor
    func qualifyingArrival_outsideWindow_returnsNil() {
        let m = makeManager()
        var start = DateComponents(); start.hour = 7; start.minute = 0
        var end = DateComponents(); end.hour = 9; end.minute = 0
        m.setWindowStart(start, for: .morning)
        m.setWindowEnd(end, for: .morning)
        let earlyMorning = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: .now)!
        let arrivals = [BusArrival(route: "38", destination: "Downtown",
                                   arrivalTime: earlyMorning.addingTimeInterval(2 * 60), now: earlyMorning)]
        #expect(m.qualifyingArrival(from: arrivals, for: .morning, at: earlyMorning) == nil)
    }

    @Test @MainActor
    func qualifyingArrival_suppressed_returnsNil() {
        let m = makeManager()
        m.suppressAtStop(for: .morning)
        let now = Date()
        let arrivals = [BusArrival(route: "38", destination: "Downtown",
                                   arrivalTime: now.addingTimeInterval(2 * 60), now: now)]
        #expect(m.qualifyingArrival(from: arrivals, for: .morning) == nil)
    }

    @Test @MainActor
    func qualifyingArrival_noReachableBus_returnsNil() {
        let m = makeManager()
        m.setTravelMinutes(30, for: .morning)
        let now = Date()
        // Bus in 20 min — unreachable (20 < 30)
        let arrivals = [BusArrival(route: "38", destination: "Downtown",
                                   arrivalTime: now.addingTimeInterval(20 * 60), now: now)]
        #expect(m.qualifyingArrival(from: arrivals, for: .morning) == nil)
    }

    @Test @MainActor
    func qualifyingArrival_reachableButNotImminent_returnsNil() {
        let m = makeManager()
        m.setTravelMinutes(30, for: .morning)
        let now = Date()
        // Bus in 40 min — reachable but > 30+5=35 min threshold
        let arrivals = [BusArrival(route: "38", destination: "Downtown",
                                   arrivalTime: now.addingTimeInterval(40 * 60), now: now)]
        #expect(m.qualifyingArrival(from: arrivals, for: .morning) == nil)
    }

    @Test @MainActor
    func qualifyingArrival_firstReachableWithinLead_returnsIt() {
        let m = makeManager()
        m.setTravelMinutes(30, for: .morning)
        let now = Date()
        // Unreachable: 20 min. Reachable and imminent: 32 min (30 <= 32 <= 35).
        let arrivals = [
            BusArrival(route: "38",  destination: "Downtown", arrivalTime: now.addingTimeInterval(20 * 60), now: now),
            BusArrival(route: "38R", destination: "Downtown", arrivalTime: now.addingTimeInterval(32 * 60), now: now)
        ]
        let result = m.qualifyingArrival(from: arrivals, for: .morning)
        #expect(result?.minutesAway == 32)
    }

    @Test @MainActor
    func qualifyingArrival_zeroTravelTime_actsLikeCurrentBehavior() {
        let m = makeManager()  // travelMinutes defaults to 0
        let now = Date()
        // Bus in 3 min — within 0+5=5 min lead
        let arrivals = [BusArrival(route: "38", destination: "Downtown",
                                   arrivalTime: now.addingTimeInterval(3 * 60), now: now)]
        #expect(m.qualifyingArrival(from: arrivals, for: .morning) != nil)
    }

    @Test @MainActor
    func qualifyingArrival_emptyArrivals_returnsNil() {
        #expect(makeManager().qualifyingArrival(from: [], for: .morning) == nil)
    }

    @Test @MainActor
    func setTravelMinutes_negativeClampsToZero() {
        let m = makeManager()
        m.setTravelMinutes(-5, for: .morning)
        #expect(m.travelMinutes(for: .morning) == 0)
    }
}
