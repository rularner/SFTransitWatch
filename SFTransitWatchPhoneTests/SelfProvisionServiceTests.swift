import XCTest
@testable import SFTransitWatchPackage

final class SelfProvisionServiceTests: XCTestCase {

    private func makeService(
        statusCode: Int = 200,
        responseBody: Data? = nil
    ) -> (SelfProvisionService, SelfProvisionMockSession) {
        let mock = SelfProvisionMockSession()
        mock.mockStatusCode = statusCode
        mock.mockData = responseBody ?? """
        {"token":"test-worker-token-abc"}
        """.data(using: .utf8)
        let service = SelfProvisionService(session: mock)
        return (service, mock)
    }

    // MARK: - Request shape

    func testProvisionSendsPOSTToSelfProvisionEndpoint() async {
        let (service, mock) = makeService()
        _ = await service.provision(workerURL: "https://worker.example.com", signedTransactionInfo: "test-jws", purpose: .purchase)
        XCTAssertEqual(mock.lastRequest?.url?.path, "/self-provision")
        XCTAssertEqual(mock.lastRequest?.httpMethod, "POST")
    }

    func testProvisionBodyIncludesSignedTransactionInfo() async throws {
        let (service, mock) = makeService()
        _ = await service.provision(workerURL: "https://worker.example.com", signedTransactionInfo: "abc.def.ghi", purpose: .purchase)

        let body = try XCTUnwrap(mock.lastRequest?.httpBody)
        let json = try JSONDecoder().decode([String: String].self, from: body)
        XCTAssertEqual(json["signedTransactionInfo"], "abc.def.ghi")
    }

    func testProvisionBodyIncludesInstallIdPlatformAndAppVersion() async throws {
        let (service, mock) = makeService()
        _ = await service.provision(workerURL: "https://worker.example.com", signedTransactionInfo: "test-jws", purpose: .purchase)

        let body = try XCTUnwrap(mock.lastRequest?.httpBody)
        let json = try JSONDecoder().decode([String: String].self, from: body)
        XCTAssertNotNil(json["install_id"])
        XCTAssertNotNil(json["platform"])
        XCTAssertNotNil(json["app_version"])
    }

    func testProvisionBodyIncludesPurpose() async throws {
        let (service, mock) = makeService()

        _ = await service.provision(workerURL: "https://worker.example.com", signedTransactionInfo: "test-jws", purpose: .purchase)
        var body = try XCTUnwrap(mock.lastRequest?.httpBody)
        var json = try JSONDecoder().decode([String: String].self, from: body)
        XCTAssertEqual(json["purpose"], "purchase")

        _ = await service.provision(workerURL: "https://worker.example.com", signedTransactionInfo: "test-jws", purpose: .refresh)
        body = try XCTUnwrap(mock.lastRequest?.httpBody)
        json = try JSONDecoder().decode([String: String].self, from: body)
        XCTAssertEqual(json["purpose"], "refresh")
    }

    // MARK: - Success path

    func testProvisionStoresTokenOnSuccess() async {
        let ud = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName)!
        ud.removeObject(forKey: "WORKER_TOKEN")
        ud.removeObject(forKey: "WORKER_BASE_URL")

        let (service, _) = makeService(statusCode: 200, responseBody: """
        {"token":"stored-token-xyz"}
        """.data(using: .utf8))

        let result = await service.provision(workerURL: "https://worker.example.com", signedTransactionInfo: "test-jws", purpose: .purchase)

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
        let result = await service.provision(workerURL: "https://worker.example.com", signedTransactionInfo: "test-jws", purpose: .purchase)
        if case .failure(let e) = result { XCTAssertEqual(e, .serverRejected) } else { XCTFail("Expected .failure(.serverRejected), got \(result)") }
    }

    func testProvisionReturnsNetworkErrorOnURLError() async {
        let mock = SelfProvisionMockSession()
        mock.mockError = URLError(.notConnectedToInternet)
        let service = SelfProvisionService(session: mock)
        let result = await service.provision(workerURL: "https://worker.example.com", signedTransactionInfo: "test-jws", purpose: .purchase)
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
