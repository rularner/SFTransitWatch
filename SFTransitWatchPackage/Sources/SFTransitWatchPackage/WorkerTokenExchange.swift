import Foundation

public protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

public class WorkerTokenExchange {
    private let session: URLSessionProtocol

    public init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    /// Exchange a one-time bootstrap code for a worker token.
    /// Sends a request to the worker's /worker-token endpoint with the code.
    /// Returns the token on success.
    public func exchange(code: String, workerURL: String) async throws -> String {
        guard let baseURL = URL(string: workerURL) else {
            throw WorkerTokenExchangeError.invalidWorkerURL
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw WorkerTokenExchangeError.invalidWorkerURL
        }

        components.path = "/worker-token"
        components.queryItems = [URLQueryItem(name: "code", value: code)]

        guard let url = components.url else {
            throw WorkerTokenExchangeError.invalidWorkerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WorkerTokenExchangeError.invalidResponse
        }

        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(TokenResponse.self, from: data)

        guard !tokenResponse.token.isEmpty else {
            throw WorkerTokenExchangeError.emptyToken
        }

        return tokenResponse.token
    }
}

struct TokenResponse: Codable {
    let token: String
}

enum WorkerTokenExchangeError: LocalizedError {
    case invalidWorkerURL
    case invalidResponse
    case emptyToken

    var errorDescription: String? {
        switch self {
        case .invalidWorkerURL:
            return "Invalid worker URL"
        case .invalidResponse:
            return "Worker returned an invalid response"
        case .emptyToken:
            return "Worker returned an empty token"
        }
    }
}
