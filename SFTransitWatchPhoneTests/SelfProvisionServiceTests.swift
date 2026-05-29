import XCTest
import CryptoKit
@testable import SFTransitWatchPackage

final class SelfProvisionServiceTests: XCTestCase {

    private static let testKey = P256.Signing.PrivateKey()

    private func makeService(
        statusCode: Int = 200,
        responseBody: Data? = nil
    ) -> (SelfProvisionService, SelfProvisionMockSession) {
        let mock = SelfProvisionMockSession()
        mock.mockStatusCode = statusCode
        mock.mockData = responseBody ?? """
        {"token":"test-worker-token-abc"}
        """.data(using: .utf8)
        let service = SelfProvisionService(privateKey: Self.testKey, session: mock)
        return (service, mock)
    }

    // MARK: - JWT shape

    func testProvisionSendsPOSTToSelfProvisionEndpoint() async {
        let (service, mock) = makeService()
        _ = await service.provision(workerURL: "https://worker.example.com")
        XCTAssertEqual(mock.lastRequest?.url?.path, "/self-provision")
        XCTAssertEqual(mock.lastRequest?.httpMethod, "POST")
    }

    func testProvisionJWTHeaderHasES256Algorithm() async throws {
        let (service, mock) = makeService()
        _ = await service.provision(workerURL: "https://worker.example.com")

        let body = try XCTUnwrap(mock.lastRequest?.httpBody)
        let json = try JSONDecoder().decode([String: String].self, from: body)
        let jwt = try XCTUnwrap(json["jwt"])
        let headerPart = try XCTUnwrap(jwt.split(separator: ".").first.map(String.init))

        var padded = headerPart.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        let headerData = try XCTUnwrap(Data(base64Encoded: padded))
        let header = try JSONDecoder().decode([String: String].self, from: headerData)

        XCTAssertEqual(header["alg"], "ES256")
        XCTAssertEqual(header["typ"], "JWT")
    }

    func testProvisionJWTPayloadContainsRequiredFields() async throws {
        let (service, mock) = makeService()
        _ = await service.provision(workerURL: "https://worker.example.com")

        let body = try XCTUnwrap(mock.lastRequest?.httpBody)
        let json = try JSONDecoder().decode([String: String].self, from: body)
        let jwt = try XCTUnwrap(json["jwt"])
        let parts = jwt.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "JWT must have three dot-separated parts")

        var padded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        let payloadData = try XCTUnwrap(Data(base64Encoded: padded))
        let payload = try JSONDecoder().decode([String: AnyCodable].self, from: payloadData)

        XCTAssertEqual(payload["iss"]?.stringValue, "org.larner.SFTransitWatch")
        XCTAssertNotNil(payload["install_id"]?.stringValue)
        XCTAssertNotNil(payload["platform"]?.stringValue)
        XCTAssertNotNil(payload["app_version"]?.stringValue)
        XCTAssertNotNil(payload["iat"]?.intValue)
        XCTAssertNotNil(payload["exp"]?.intValue)
    }

    func testProvisionJWTExpIsIatPlusSixty() async throws {
        let (service, mock) = makeService()
        let before = Int(Date().timeIntervalSince1970)
        _ = await service.provision(workerURL: "https://worker.example.com")
        let after = Int(Date().timeIntervalSince1970)

        let body = try XCTUnwrap(mock.lastRequest?.httpBody)
        let json = try JSONDecoder().decode([String: String].self, from: body)
        let jwt = try XCTUnwrap(json["jwt"])
        let parts = jwt.split(separator: ".")
        var padded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        let payload = try JSONDecoder().decode([String: AnyCodable].self, from: Data(base64Encoded: padded)!)

        let iat = try XCTUnwrap(payload["iat"]?.intValue)
        let exp = try XCTUnwrap(payload["exp"]?.intValue)
        XCTAssertGreaterThanOrEqual(iat, before)
        XCTAssertLessThanOrEqual(iat, after)
        XCTAssertEqual(exp, iat + 60)
    }

    // MARK: - Success path

    func testProvisionStoresTokenOnSuccess() async {
        let ud = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName)!
        ud.removeObject(forKey: "WORKER_TOKEN")
        ud.removeObject(forKey: "WORKER_BASE_URL")

        let (service, _) = makeService(statusCode: 200, responseBody: """
        {"token":"stored-token-xyz"}
        """.data(using: .utf8))

        let result = await service.provision(workerURL: "https://worker.example.com")

        if case .success = result { } else { XCTFail("Expected .success, got \(result)") }
        XCTAssertEqual(ConfigurationManager.shared.workerToken, "stored-token-xyz")
        XCTAssertEqual(ConfigurationManager.shared.workerBaseURL, "https://worker.example.com")

        ud.removeObject(forKey: "WORKER_TOKEN")
        ud.removeObject(forKey: "WORKER_BASE_URL")
    }

    // MARK: - Failure paths

    func testProvisionReturnsServerRejectedOn401() async {
        let (service, _) = makeService(statusCode: 401, responseBody: """
        {"error":"Unauthorized"}
        """.data(using: .utf8))
        let result = await service.provision(workerURL: "https://worker.example.com")
        if case .failure(let e) = result { XCTAssertEqual(e, .serverRejected) } else { XCTFail("Expected .failure(.serverRejected), got \(result)") }
    }

    func testProvisionReturnsNetworkErrorOnURLError() async {
        let mock = SelfProvisionMockSession()
        mock.mockError = URLError(.notConnectedToInternet)
        let service = SelfProvisionService(privateKey: Self.testKey, session: mock)
        let result = await service.provision(workerURL: "https://worker.example.com")
        if case .failure(let e) = result { XCTAssertEqual(e, .networkError) } else { XCTFail("Expected .failure(.networkError), got \(result)") }
    }
}

// MARK: - Test helpers

final class SelfProvisionMockSession: URLSessionProtocol {
    var mockData: Data?
    var mockError: Error?
    var mockStatusCode: Int = 200
    var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error = mockError { throw error }
        let data = mockData ?? Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private struct AnyCodable: Decodable {
    let stringValue: String?
    let intValue: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            stringValue = s; intValue = nil
        } else if let i = try? container.decode(Int.self) {
            intValue = i; stringValue = nil
        } else {
            stringValue = nil; intValue = nil
        }
    }
}
