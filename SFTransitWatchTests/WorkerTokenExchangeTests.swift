import XCTest
@testable import SFTransitWatchPackage

class WorkerTokenExchangeTests: XCTestCase {

    func testExchangeBootstrapCodeForToken() async {
        let mockSession = MockURLSession()
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
        let mockSession = MockURLSession()
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
        let mockSession = MockURLSession()
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
}

// Mock for testing
class MockURLSession: URLSessionProtocol {
    var mockData: Data?
    var mockError: Error?
    var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error = mockError {
            throw error
        }
        let data = mockData ?? Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
