import XCTest
@testable import SFTransitWatch

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

}
