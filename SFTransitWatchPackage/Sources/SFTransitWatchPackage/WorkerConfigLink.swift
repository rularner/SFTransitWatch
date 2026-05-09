import Foundation

public enum WorkerConfigLink {
    public static func apiKey(from url: URL) -> String? {
        // sftransitwatch://key/YOUR_API_KEY
        if url.scheme == "sftransitwatch", url.host == "key" {
            return String(url.path.dropFirst())
        }
        // https://rularner.github.io/sftransitwatch/key?k=YOUR_KEY
        if url.scheme == "https",
           url.host == "rularner.github.io",
           url.path == "/sftransitwatch/key",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            return components.queryItems?.first { $0.name == "k" }?.value
        }
        return nil
    }

    /// Parses a worker bootstrap link in either form:
    ///   sftransitwatch://wt?u=<encoded-worker-url>&t=<token>
    ///   https://rularner.github.io/sftransitwatch/wt?u=<encoded-worker-url>&t=<token>
    /// Returns nil if either parameter is missing or empty. Worker URLs without
    /// an https scheme are rejected to keep tokens off the wire in cleartext.
    public static func workerConfig(from url: URL) -> (url: String, token: String)? {
        let isCustomScheme = url.scheme == "sftransitwatch" && url.host == "wt"
        let isUniversal = url.scheme == "https"
            && url.host == "rularner.github.io"
            && url.path == "/sftransitwatch/wt"
        guard isCustomScheme || isUniversal else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        guard let workerURL = items.first(where: { $0.name == "u" })?.value, !workerURL.isEmpty,
              let token = items.first(where: { $0.name == "t" })?.value, !token.isEmpty,
              let parsed = URL(string: workerURL),
              parsed.scheme == "https" else { return nil }
        return (url: workerURL, token: token)
    }
}
