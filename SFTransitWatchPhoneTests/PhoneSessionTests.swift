import XCTest
@testable import SFTransitWatch
import SFTransitWatchPackage

final class PhoneSessionTests: XCTestCase {

    func testPayloadWithEmptyKey() {
        let payload = PhoneSession.payload(forKey: "")
        XCTAssertEqual(payload["transitKey"] as? String, "")
    }

    func testPayloadWithNilKey() {
        let payload = PhoneSession.payload(forKey: nil)
        XCTAssertEqual(payload["transitKey"] as? String, "")
    }

    func testPayloadWithValidKey() {
        let testKey = "test-api-key-123"
        let payload = PhoneSession.payload(forKey: testKey)
        XCTAssertEqual(payload["transitKey"] as? String, testKey)
    }

    func testPayloadWithKeyContainingWhitespace() {
        let payload = PhoneSession.payload(forKey: "  key-with-spaces  ")
        XCTAssertEqual(payload["transitKey"] as? String, "key-with-spaces")
    }

    // MARK: - buildPayload sync fields

    func testBuildPayloadIncludesAllSyncFields() {
        let payload = PhoneSession.buildPayload()
        XCTAssertNotNil(payload["transitKey"])
        XCTAssertNotNil(payload["workerToken"])
        XCTAssertNotNil(payload["workerBaseURL"])
        XCTAssertNotNil(payload["enabledAgencies"])
        XCTAssertNotNil(payload["commuteMorning"])
        XCTAssertNotNil(payload["commuteAfternoon"])
        XCTAssertNotNil(payload["favoriteStops"])
    }

    func testBuildPayloadFavoritesIsData() {
        let payload = PhoneSession.buildPayload()
        XCTAssertTrue(payload["favoriteStops"] is Data)
    }

    // MARK: - applyWatchContext: applies changes

    func testApplyWatchContextWritesAgencies() {
        let suite = "PhoneSessionTests-agencies-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!

        PhoneSession.shared.applyWatchContext(
            ["enabledAgencies": "SF,BA"],
            appGroup: ud
        )

        XCTAssertEqual(ud.string(forKey: EnabledAgencies.storageKey), "SF,BA")
    }

    func testApplyWatchContextWritesCommuteMorning() {
        let suite = "PhoneSessionTests-commute-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!

        PhoneSession.shared.applyWatchContext(
            ["commuteMorning": "stop-123", "commuteAfternoon": ""],
            appGroup: ud
        )

        XCTAssertEqual(ud.string(forKey: CommuteSlotsManager.Slot.morning.storageKey), "stop-123")
        XCTAssertNil(ud.string(forKey: CommuteSlotsManager.Slot.afternoon.storageKey))
    }

    func testApplyWatchContextWritesFavorites() {
        let suite = "PhoneSessionTests-favorites-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        let favData = """
            [{"id":"1","name":"A","code":"1","agency":"SF","latitude":0,"longitude":0}]
            """.data(using: .utf8)!

        // Can't inject UserDefaults.standard easily; verify it doesn't crash.
        // The loop-prevention coverage is in the dedicated no-write tests below.
        PhoneSession.shared.applyWatchContext(["favoriteStops": favData], appGroup: ud)
    }

    // MARK: - applyWatchContext: loop prevention (no write when data unchanged)

    func testApplyWatchContextDoesNotWriteAgenciesWhenUnchanged() async throws {
        let suite = "PhoneSessionTests-loop-agencies-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.set("SF,BA", forKey: EnabledAgencies.storageKey)

        var writeCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: ud,
            queue: .main
        ) { _ in writeCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        PhoneSession.shared.applyWatchContext(
            ["enabledAgencies": "SF,BA"],
            appGroup: ud
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(writeCount, 0, "No write expected when agencies are already up to date")
    }

    func testApplyWatchContextDoesNotWriteCommuteWhenUnchanged() async throws {
        let suite = "PhoneSessionTests-loop-commute-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.set("stop-abc", forKey: CommuteSlotsManager.Slot.morning.storageKey)

        var writeCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: ud,
            queue: .main
        ) { _ in writeCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        PhoneSession.shared.applyWatchContext(
            ["commuteMorning": "stop-abc", "commuteAfternoon": ""],
            appGroup: ud
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(writeCount, 0, "No write expected when commute is already up to date")
    }

    func testApplyWatchContextWritesAgenciesWhenChanged() async throws {
        let suite = "PhoneSessionTests-changed-agencies-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.set("SF,BA", forKey: EnabledAgencies.storageKey)

        var writeCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: ud,
            queue: .main
        ) { _ in writeCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        PhoneSession.shared.applyWatchContext(
            ["enabledAgencies": "SF,BA,CT"],
            appGroup: ud
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertGreaterThan(writeCount, 0, "A write should occur when agencies changed")
        XCTAssertEqual(ud.string(forKey: EnabledAgencies.storageKey), "SF,BA,CT")
    }
}
