import XCTest
import SFTransitWatchPackage

@MainActor
final class SharedAgenciesManagerTests: XCTestCase {

    private var manager: SharedAgenciesManager!

    override func setUp() async throws {
        let suite = "SharedAgenciesManagerTests-\(UUID().uuidString)"
        manager = SharedAgenciesManager(userDefaultsSuiteName: suite)
    }

    func testDefaultEnablesAllKnownAgencies() {
        XCTAssertEqual(manager.enabledCodes, Set(Agency.known.map(\.code)))
    }

    func testToggleDisablesEnabledAgency() {
        manager.toggle("SF")
        XCTAssertFalse(manager.isEnabled("SF"))
    }

    func testToggleReEnablesDisabledAgency() {
        manager.toggle("SF")
        manager.toggle("SF")
        XCTAssertTrue(manager.isEnabled("SF"))
    }

    func testIsEnabledReturnsTrueForEnabledCode() {
        XCTAssertTrue(manager.isEnabled("SF"))
    }

    func testIsEnabledReturnsFalseForDisabledCode() {
        manager.toggle("SF")
        XCTAssertFalse(manager.isEnabled("SF"))
    }

    func testSetEnabledReplacesSelection() {
        manager.setEnabled(["SF", "BA"])
        XCTAssertEqual(manager.enabledCodes, ["SF", "BA"])
    }

    func testAsArrayPreservesKnownOrder() {
        manager.setEnabled(["CT", "SF", "BA"])
        XCTAssertEqual(manager.asArray, ["SF", "BA", "CT"])
    }

    func testPersistenceAcrossInstances() {
        let suite = "SharedAgenciesManagerTests-persist-\(UUID().uuidString)"
        let first = SharedAgenciesManager(userDefaultsSuiteName: suite)
        first.toggle("SF")

        let second = SharedAgenciesManager(userDefaultsSuiteName: suite)
        XCTAssertFalse(second.isEnabled("SF"))
        XCTAssertTrue(second.isEnabled("BA"))
    }

    func testAsArrayExcludesDisabledCodes() {
        manager.toggle("SF")
        XCTAssertFalse(manager.asArray.contains("SF"))
    }

    // MARK: - External reload (WatchConnectivity sync)

    func testExternalWriteReloadsEnabledCodes() async throws {
        let suite = "SharedAgenciesManagerTests-external-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        let mgr = SharedAgenciesManager(userDefaultsSuiteName: suite)

        XCTAssertTrue(mgr.isEnabled("SF"), "SF should be enabled by default")

        // Simulate WatchConnectivity writing directly to UserDefaults
        ud.set(EnabledAgencies.format(["BA", "CT"]), forKey: EnabledAgencies.storageKey)

        // Wait for UserDefaults.didChangeNotification to propagate
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(mgr.isEnabled("SF"), "SF should be disabled after external write")
        XCTAssertTrue(mgr.isEnabled("BA"))
        XCTAssertTrue(mgr.isEnabled("CT"))
    }

    func testExternalWriteWithSameValueDoesNotChangeState() async throws {
        let suite = "SharedAgenciesManagerTests-noop-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        let mgr = SharedAgenciesManager(userDefaultsSuiteName: suite)
        mgr.toggle("SF") // disable SF → stored as all-except-SF

        let beforeCodes = mgr.enabledCodes

        // Write the same value externally
        ud.set(ud.string(forKey: EnabledAgencies.storageKey), forKey: EnabledAgencies.storageKey)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mgr.enabledCodes, beforeCodes, "State should be unchanged after a no-op write")
    }
}
