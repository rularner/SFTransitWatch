import Foundation
@testable import SFTransitWatch_Watch_App

class MockURLSession: URLSessionProtocol {
    // `data(for:)` is called concurrently by tests that fan out one request per
    // agency (e.g. searchStops via withTaskGroup) — an unsynchronized array append
    // there is a data race that silently drops requests under real concurrency.
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var responses: [URL: (data: Data, response: HTTPURLResponse)] = [:]
    var errors: [URL: Error] = [:]

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _requests.append(request) }

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

        // Try to match by host + path (ignores query params — allows multiple endpoints on same host)
        if let match = responses.first(where: { $0.key.host == url.host && $0.key.path == url.path }) {
            return match.value
        }

        // Try to match by host only (most lenient matching)
        if let match = responses.first(where: { $0.key.host == url.host }) {
            return match.value
        }

        // Default 404 if not configured
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
    }

    func setMockResponse(for url: URL, data: Data, statusCode: Int = 200, headers: [String: String]? = nil) {
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        responses[url] = (data, response)
    }

    func setMockError(for url: URL, error: Error) {
        errors[url] = error
    }

    func lastRequest() -> URLRequest? {
        lock.withLock { _requests.last }
    }

    func requestCount() -> Int {
        lock.withLock { _requests.count }
    }

    func clearHistory() {
        lock.withLock { _requests.removeAll() }
        responses.removeAll()
        errors.removeAll()
    }
}
