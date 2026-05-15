import Foundation

public enum WorkerConfigLink {
    public static func apiKey(from url: URL) -> String? {
        // sftransitwatch://key/YOUR_API_KEY
        if url.scheme == "sftransitwatch", url.host == "key" {
            return String(url.path.dropFirst())
        }
        return nil
    }

    /// Parses a worker bootstrap link in the form:
    ///   sftransitwatch://wt?u=<encoded-worker-url>&c=<one-time-code>
    /// Returns nil if either parameter is missing or empty. Worker URLs without
    /// an https scheme are rejected to keep tokens off the wire in cleartext.
    public static func workerBootstrap(from url: URL) -> (url: String, code: String)? {
        let isCustomScheme = url.scheme == "sftransitwatch" && url.host == "wt"
        guard isCustomScheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        guard let workerURL = items.first(where: { $0.name == "u" })?.value, !workerURL.isEmpty,
              let code = items.first(where: { $0.name == "c" })?.value, !code.isEmpty,
              let parsed = URL(string: workerURL),
              parsed.scheme == "https" else { return nil }
        return (url: workerURL, code: code)
    }
}
