import Foundation
import Testing
@testable import SFTransitWatchPackage

@Suite(.serialized)
@MainActor
struct CommuteSlotsManagerTests {

    // MARK: - Basic operations

    @Test func initiallyEmpty() {
        let mgr = CommuteSlotsManager(userDefaultsSuiteName: nil)
        #expect(mgr.morningStopId == nil)
        #expect(mgr.afternoonStopId == nil)
    }

    @Test func setAndGetMorningStop() {
        let suite = "CommuteSlotsManagerTests-set-\(UUID().uuidString)"
        let mgr = CommuteSlotsManager(userDefaultsSuiteName: suite)
        mgr.setStopId("stop-1", for: .morning)
        #expect(mgr.stopId(for: .morning) == "stop-1")
        #expect(mgr.stopId(for: .afternoon) == nil)
    }

    @Test func clearStop() {
        let suite = "CommuteSlotsManagerTests-clear-\(UUID().uuidString)"
        let mgr = CommuteSlotsManager(userDefaultsSuiteName: suite)
        mgr.setStopId("stop-1", for: .morning)
        mgr.setStopId(nil, for: .morning)
        #expect(mgr.stopId(for: .morning) == nil)
    }

    @Test func slotForStopId() {
        let suite = "CommuteSlotsManagerTests-slot-\(UUID().uuidString)"
        let mgr = CommuteSlotsManager(userDefaultsSuiteName: suite)
        mgr.setStopId("stop-am", for: .morning)
        mgr.setStopId("stop-pm", for: .afternoon)
        #expect(mgr.slot(for: "stop-am") == .morning)
        #expect(mgr.slot(for: "stop-pm") == .afternoon)
        #expect(mgr.slot(for: "unknown") == nil)
    }

    @Test func activeSlotWithFallbackPrefersActiveSlot() {
        let suite = "CommuteSlotsManagerTests-active-\(UUID().uuidString)"
        let mgr = CommuteSlotsManager(userDefaultsSuiteName: suite)
        mgr.setStopId("stop-am", for: .morning)
        mgr.setStopId("stop-pm", for: .afternoon)

        // 8am → morning
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
        #expect(mgr.activeSlotWithFallback(at: morning) == .morning)

        // 5pm → afternoon
        let afternoon = cal.date(bySettingHour: 17, minute: 0, second: 0, of: .now)!
        #expect(mgr.activeSlotWithFallback(at: afternoon) == .afternoon)
    }

    @Test func activeSlotWithFallbackFallsBackWhenActiveIsEmpty() {
        let suite = "CommuteSlotsManagerTests-fallback-\(UUID().uuidString)"
        let mgr = CommuteSlotsManager(userDefaultsSuiteName: suite)
        mgr.setStopId(nil, for: .morning)
        mgr.setStopId("stop-pm", for: .afternoon)

        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
        #expect(mgr.activeSlotWithFallback(at: morning) == .afternoon)
    }

    @Test func persistenceAcrossInstances() {
        let suite = "CommuteSlotsManagerTests-persist-\(UUID().uuidString)"
        let first = CommuteSlotsManager(userDefaultsSuiteName: suite)
        first.setStopId("stop-x", for: .morning)

        let second = CommuteSlotsManager(userDefaultsSuiteName: suite)
        #expect(second.stopId(for: .morning) == "stop-x")
    }

    // MARK: - External reload (WatchConnectivity sync)

    @Test func externalWriteReloadsPublishedProperties() async throws {
        let suite = "CommuteSlotsManagerTests-external-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        let mgr = CommuteSlotsManager(userDefaultsSuiteName: suite)

        #expect(mgr.morningStopId == nil)

        // Simulate WatchConnectivity writing directly to UserDefaults
        ud.set("stop-sync", forKey: CommuteSlotsManager.Slot.morning.storageKey)

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(mgr.morningStopId == "stop-sync")
    }

    @Test func externalClearReloadsPublishedProperties() async throws {
        let suite = "CommuteSlotsManagerTests-extclear-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        let mgr = CommuteSlotsManager(userDefaultsSuiteName: suite)
        mgr.setStopId("stop-abc", for: .afternoon)
        #expect(mgr.afternoonStopId == "stop-abc")

        ud.removeObject(forKey: CommuteSlotsManager.Slot.afternoon.storageKey)

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(mgr.afternoonStopId == nil)
    }

    @Test func externalWriteWithSameValueDoesNotChangePublishedProperty() async throws {
        let suite = "CommuteSlotsManagerTests-noop-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        let mgr = CommuteSlotsManager(userDefaultsSuiteName: suite)
        mgr.setStopId("stop-stable", for: .morning)

        // Write the same value externally
        ud.set("stop-stable", forKey: CommuteSlotsManager.Slot.morning.storageKey)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Value is unchanged — no spurious @Published update should have clobbered anything
        #expect(mgr.morningStopId == "stop-stable")
    }
}
