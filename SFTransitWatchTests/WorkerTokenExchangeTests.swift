import XCTest
@testable import SFTransitWatchPackage

class WorkerTokenExchangeTests: XCTestCase {

    func testExchangeBootstrapCodeForToken() async {
        let mockSession = SimpleURLSessionMock()
        let exchange = WorkerTokenExchange(session: mockSession)

        let testWorkerURL = "https://api.example.com"
        let testCode = "bootstrap-code-123"
        let expectedToken = "worker-token-xyz"

        mockSession.mockData = """
        {"token": "\(expectedToken)"}
        """.data(using: .utf8)

        do {
            let token = try await exchange.exchange(code: testCode, workerURL: testWorkerURL)
            XCTAssertEqual(token, expectedToken)
        } catch {
            XCTFail("Expected successful token exchange, got error: \(error)")
        }
    }

    func testExchangeThrowsOnInvalidResponse() async {
        let mockSession = SimpleURLSessionMock()
        let exchange = WorkerTokenExchange(session: mockSession)

        mockSession.mockData = "invalid json".data(using: .utf8)

        do {
            _ = try await exchange.exchange(code: "code", workerURL: "https://api.example.com")
            XCTFail("Expected decoding error")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testExchangeThrowsOnNetworkError() async {
        let mockSession = SimpleURLSessionMock()
        let exchange = WorkerTokenExchange(session: mockSession)

        mockSession.mockError = URLError(.notConnectedToInternet)

        do {
            _ = try await exchange.exchange(code: "code", workerURL: "https://api.example.com")
            XCTFail("Expected network error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Expected URLError")
        }
    }

    func testExchangeThrowsOnHTTPError() async {
        let mockSession = SimpleURLSessionMock()
        let exchange = WorkerTokenExchange(session: mockSession)

        mockSession.mockStatusCode = 401
        mockSession.mockData = """
        {"error": "Unauthorized"}
        """.data(using: .utf8)

        do {
            _ = try await exchange.exchange(code: "code", workerURL: "https://api.example.com")
            XCTFail("Expected invalidResponse error for non-200 status")
        } catch let error as WorkerTokenExchangeError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Expected WorkerTokenExchangeError, got: \(error)")
        }
    }
}

// Mock for testing
//
// `final` + `@unchecked Sendable` + lock-guarded state, matching the pattern used by
// `SFTransitWatchPackageTests/MockURLSession.swift` — required because `URLSessionProtocol`
// is `Sendable` (see commit 7b93565).
final class SimpleURLSessionMock: URLSessionProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private var _mockData: Data?
    private var _mockError: Error?
    private var _mockStatusCode: Int = 200
    private var _lastRequest: URLRequest?

    var mockData: Data? {
        get { lock.withLock { _mockData } }
        set { lock.withLock { _mockData = newValue } }
    }
    var mockError: Error? {
        get { lock.withLock { _mockError } }
        set { lock.withLock { _mockError = newValue } }
    }
    var mockStatusCode: Int {
        get { lock.withLock { _mockStatusCode } }
        set { lock.withLock { _mockStatusCode = newValue } }
    }
    var lastRequest: URLRequest? {
        get { lock.withLock { _lastRequest } }
        set { lock.withLock { _lastRequest = newValue } }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error = mockError {
            throw error
        }
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
