import Foundation
@testable import SFTransitWatchPackage

/// Test double for `URLSessionProtocol`, shared by the package's `TransitAPI` tests (and,
/// pending Tasks 3–4, by the migrated phone/watch suites).
///
/// `TransitAPI.fetchNearbyStops`/`searchStops` fan out one request per agency via
/// `withTaskGroup`, so `data(for:)` genuinely is called concurrently from multiple
/// non-`MainActor` child tasks — this isn't a hypothetical. `URLSessionProtocol` requires
/// `Sendable`, and `@unchecked Sendable` is only an honest claim here because every piece of
/// mutable state (including the properties tests assign directly, like `responses` and
/// `delaySeconds`) is routed through `lock` rather than left as a bare `var`.
final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private var _requests: [URLRequest] = []
    private var _responses: [URL: (data: Data, response: HTTPURLResponse)] = [:]
    private var _errors: [URL: Error] = [:]
    private var _delaySeconds: Double = 0

    /// Direct stub access (e.g. `mockSession.responses[url] = (data, response)`), guarded by
    /// `lock` under the hood so it's safe even though `data(for:)` may be reading it
    /// concurrently from task-group child tasks.
    var responses: [URL: (data: Data, response: HTTPURLResponse)] {
        get { lock.withLock { _responses } }
        set { lock.withLock { _responses = newValue } }
    }

    var errors: [URL: Error] {
        get { lock.withLock { _errors } }
        set { lock.withLock { _errors = newValue } }
    }

    /// Artificial delay (in seconds) before each response — honours task cancellation.
    var delaySeconds: Double {
        get { lock.withLock { _delaySeconds } }
        set { lock.withLock { _delaySeconds = newValue } }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let delay = lock.withLock { _delaySeconds }
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        lock.withLock { _requests.append(request) }

        guard let url = request.url else {
            throw URLError(.badURL)
        }

        // Snapshot both dictionaries under one lock acquisition so a concurrent
        // setMockResponse/setMockError from another task can't be interleaved
        // between the errors check and the responses check below.
        let (responsesSnapshot, errorsSnapshot) = lock.withLock { (_responses, _errors) }

        if let error = errorsSnapshot[url] {
            throw error
        }
        if let match = errorsSnapshot.first(where: { $0.key.host == url.host }) {
            throw match.value
        }
        if let (data, response) = responsesSnapshot[url] {
            return (data, response)
        }
        // Try to match by host + path (ignores query params — allows multiple endpoints on same host)
        if let match = responsesSnapshot.first(where: { $0.key.host == url.host && $0.key.path == url.path }) {
            return match.value
        }
        // Try to match by host only (most lenient matching)
        if let match = responsesSnapshot.first(where: { $0.key.host == url.host }) {
            return match.value
        }
        // Default 404 if not configured
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
    }

    func setMockResponse(for url: URL, data: Data, statusCode: Int = 200, headers: [String: String]? = nil) {
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        lock.withLock { _responses[url] = (data, response) }
    }

    func setMockError(for url: URL, error: Error) {
        lock.withLock { _errors[url] = error }
    }

    func lastRequest() -> URLRequest? {
        lock.withLock { _requests.last }
    }

    func requestCount() -> Int {
        lock.withLock { _requests.count }
    }

    func recordedRequests() -> [URLRequest] {
        lock.withLock { _requests }
    }

    func clearHistory() {
        lock.withLock {
            _requests.removeAll()
            _responses.removeAll()
            _errors.removeAll()
        }
    }
}
