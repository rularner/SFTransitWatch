import Foundation
@testable import SFTransitWatch_Watch_App

class MockURLSession: URLSessionProtocol {
    var requests: [URLRequest] = []
    var responses: [URL: (data: Data, response: HTTPURLResponse)] = [:]
    var errors: [URL: Error] = [:]

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        guard let url = request.url else {
            throw URLError(.badURL)
        }

        if let error = errors[url] {
            throw error
        }

        if let match = errors.first(where: { $0.key.host == url.host }) {
            throw match.value
        }

        if let (data, response) = responses[url] {
            return (data, response)
        }

        // Try to match by host only (most lenient matching)
        if let match = responses.first(where: { $0.key.host == url.host }) {
            return match.value
        }

        // Default 404 if not configured
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
    }

    func setMockResponse(for url: URL, data: Data, statusCode: Int = 200) {
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        responses[url] = (data, response)
    }

    func setMockError(for url: URL, error: Error) {
        errors[url] = error
    }

    func lastRequest() -> URLRequest? {
        return requests.last
    }

    func requestCount() -> Int {
        return requests.count
    }

    func clearHistory() {
        requests.removeAll()
        responses.removeAll()
        errors.removeAll()
    }
}
