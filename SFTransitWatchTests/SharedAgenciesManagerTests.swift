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
}
