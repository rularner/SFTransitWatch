import XCTest
import SFTransitWatchPackage

final class EnabledAgenciesTests: XCTestCase {
    func testParseSplitsCommaSeparatedCodes() {
        XCTAssertEqual(EnabledAgencies.parse("SF,BA"), ["SF", "BA"])
    }

    func testParseTrimsWhitespaceAroundCodes() {
        XCTAssertEqual(EnabledAgencies.parse(" SF , BA "), ["SF", "BA"])
    }

    func testParseEmptyStringFallsBackToAllKnownAgencies() {
        XCTAssertEqual(EnabledAgencies.parse(""), Agency.known.map(\.code))
    }

    /// Regression: a stored value of just "," (or other whitespace-only
    /// separators) used to fall back to `[Self.default]`, a single-element
    /// array containing the *joined* default string ("SF,BA,AC,...") rather
    /// than a real agency code. That bogus code matched no `Agency`, so every
    /// real agency silently ended up disabled.
    func testParseCommaOnlyFallsBackToAllKnownAgencies() {
        let result = EnabledAgencies.parse(",")
        XCTAssertEqual(result, Agency.known.map(\.code))
        XCTAssertTrue(result.allSatisfy { Agency.named($0) != nil })
    }

    func testParseWhitespaceOnlyFallsBackToAllKnownAgencies() {
        let result = EnabledAgencies.parse("  ,  ,  ")
        XCTAssertEqual(result, Agency.known.map(\.code))
        XCTAssertTrue(result.allSatisfy { Agency.named($0) != nil })
    }

    func testDefaultAgencyUsesFirstParsedCode() {
        XCTAssertEqual(EnabledAgencies.defaultAgency("BA,SF"), "BA")
    }

    func testDefaultAgencyFallsBackToMuniWhenStoredIsUnparseable() {
        XCTAssertEqual(EnabledAgencies.defaultAgency(","), Agency.muni.code)
    }
}
