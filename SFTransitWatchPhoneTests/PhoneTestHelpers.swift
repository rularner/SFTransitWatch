import Foundation
@testable import SFTransitWatch

class MockURLSession: URLSessionProtocol {
    var requests: [URLRequest] = []
    var responses: [URL: (data: Data, response: HTTPURLResponse)] = [:]
    var errors: [URL: Error] = [:]

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url else { throw URLError(.badURL) }
        if let error = errors[url] { throw error }
        if let match = errors.first(where: { $0.key.host == url.host }) { throw match.value }
        if let (data, response) = responses[url] { return (data, response) }
        if let match = responses.first(where: { $0.key.host == url.host }) {
            return match.value
        }
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
    }

    func setMockResponse(for url: URL, data: Data, statusCode: Int = 200) {
        let resp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        responses[url] = (data: data, response: resp)
    }

    func setMockError(for url: URL, error: Error) { errors[url] = error }
    func requestCount() -> Int { requests.count }
}
