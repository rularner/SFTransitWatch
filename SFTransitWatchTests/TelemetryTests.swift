import XCTest
@testable import SFTransitWatch_Watch_App

final class TelemetryTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "TelemetryTests-\(UUID().uuidString)")!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
        defaults = nil
        super.tearDown()
    }

    func testInstallIdIsStableAcrossInstances() {
        let a = Telemetry(defaults: defaults, token: nil, baseURL: nil, platform: "watch", appVersion: "1.0", build: "1")
        let b = Telemetry(defaults: defaults, token: nil, baseURL: nil, platform: "watch", appVersion: "1.0", build: "1")
        XCTAssertEqual(a.installId, b.installId)
    }

    func testInstallIdRegeneratesAfterDefaultsWipe() {
        let a = Telemetry(defaults: defaults, token: nil, baseURL: nil, platform: "watch", appVersion: "1.0", build: "1")
        let firstId = a.installId
        defaults.removeObject(forKey: "telemetry.install_id")
        let b = Telemetry(defaults: defaults, token: nil, baseURL: nil, platform: "watch", appVersion: "1.0", build: "1")
        XCTAssertNotEqual(b.installId, firstId)
    }

    func testRingBufferCapsAt50() {
        let t = Telemetry(defaults: defaults, token: "tok", baseURL: "https://x.example", platform: "watch", appVersion: "1.0", build: "1")
        for _ in 0..<60 {
            t.logFetchOutcome(endpoint: "StopMonitoring", httpStatus: 200, latencyMs: 100, cacheStatus: "HIT")
        }
        XCTAssertEqual(t.bufferedEventsForTesting.count, 50)
    }

    func testRingBufferEvictsOldestFirst() {
        let t = Telemetry(defaults: defaults, token: "tok", baseURL: "https://x.example", platform: "watch", appVersion: "1.0", build: "1")
        for i in 0..<60 {
            t.logFetchOutcome(endpoint: "StopMonitoring", httpStatus: i, latencyMs: 100, cacheStatus: nil)
        }
        // After 60 inserts with cap 50, the oldest 10 are gone — first remaining is i=10.
        XCTAssertEqual(t.bufferedEventsForTesting.first?.httpStatus, 10)
        XCTAssertEqual(t.bufferedEventsForTesting.last?.httpStatus, 59)
    }

    func testNoOpWhenTokenMissing() {
        let t = Telemetry(defaults: defaults, token: nil, baseURL: "https://x.example", platform: "watch", appVersion: "1.0", build: "1")
        t.logFetchOutcome(endpoint: "StopMonitoring", httpStatus: 200, latencyMs: 100, cacheStatus: "HIT")
        XCTAssertTrue(t.bufferedEventsForTesting.isEmpty)
    }

    func testNoOpWhenBaseURLMissing() {
        let t = Telemetry(defaults: defaults, token: "tok", baseURL: nil, platform: "watch", appVersion: "1.0", build: "1")
        t.logFetchOutcome(endpoint: "StopMonitoring", httpStatus: 200, latencyMs: 100, cacheStatus: "HIT")
        XCTAssertTrue(t.bufferedEventsForTesting.isEmpty)
    }

    func testEventEncodingMatchesSchema() throws {
        let t = Telemetry(defaults: defaults, token: "tok", baseURL: "https://x.example", platform: "watch", appVersion: "1.4.2", build: "42")
        t.logFetchError(endpoint: "StopPlace", errorKind: "http_5xx", httpStatus: 503, latencyMs: 1234)
        guard let event = t.bufferedEventsForTesting.first else {
            return XCTFail("expected one event")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(event)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"app_version\":\"1.4.2\""))
        XCTAssertTrue(json.contains("\"build\":\"42\""))
        XCTAssertTrue(json.contains("\"endpoint\":\"StopPlace\""))
        XCTAssertTrue(json.contains("\"error_kind\":\"http_5xx\""))
        XCTAssertTrue(json.contains("\"http_status\":503"))
        XCTAssertTrue(json.contains("\"kind\":\"fetch_error\""))
        XCTAssertTrue(json.contains("\"latency_ms\":1234"))
        XCTAssertTrue(json.contains("\"platform\":\"watch\""))
        XCTAssertTrue(json.contains("\"install_id\":"))
        XCTAssertTrue(json.contains("\"ts\":"))
    }

    func testOutcomeEventOmitsErrorKind() throws {
        let t = Telemetry(defaults: defaults, token: "tok", baseURL: "https://x.example", platform: "watch", appVersion: "1.0", build: "1")
        t.logFetchOutcome(endpoint: "StopMonitoring", httpStatus: 200, latencyMs: 100, cacheStatus: "HIT")
        let event = t.bufferedEventsForTesting.first!
        XCTAssertNil(event.errorKind)
        XCTAssertEqual(event.kind, "fetch_outcome")
        XCTAssertEqual(event.cacheStatus, "HIT")
    }
}
