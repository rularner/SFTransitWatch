import Foundation
import os

struct TelemetryEvent: Codable, Equatable {
    let ts: String
    let installId: String
    let platform: String
    let appVersion: String
    let build: String
    let kind: String
    let endpoint: String
    let httpStatus: Int?
    let latencyMs: Int
    let errorKind: String?
    let cacheStatus: String?

    enum CodingKeys: String, CodingKey {
        case ts
        case installId = "install_id"
        case platform
        case appVersion = "app_version"
        case build
        case kind
        case endpoint
        case httpStatus = "http_status"
        case latencyMs = "latency_ms"
        case errorKind = "error_kind"
        case cacheStatus = "cache_status"
    }
}

final class Telemetry {
    static let shared = Telemetry()

    private static let installIdKey = "telemetry.install_id"
    private static let bufferCap = 50
    private static let debounceSeconds: TimeInterval = 5

    private let logger = Logger(subsystem: "org.larner.SFTransitWatch", category: "telemetry")
    private let queue = DispatchQueue(label: "org.larner.SFTransitWatch.telemetry")
    private let session: URLSession
    private let defaults: UserDefaults
    private let token: String?
    private let baseURL: String?
    private let platform: String
    private let appVersion: String
    private let build: String

    private var buffer: [TelemetryEvent] = []
    private var debounceWorkItem: DispatchWorkItem?
    private var flushInFlight = false

    let installId: String

    var isEnabled: Bool {
        guard let token, !token.isEmpty, let baseURL, !baseURL.isEmpty else { return false }
        return true
    }

    convenience init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let token = (info["APP_TOKEN"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let baseURL = (info["TELEMETRY_BASE_URL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let appVersion = (info["CFBundleShortVersionString"] as? String) ?? "0"
        let build = (info["CFBundleVersion"] as? String) ?? "0"
        #if os(watchOS)
        let platform = "watch"
        #else
        let platform = "ios"
        #endif
        self.init(
            defaults: .standard,
            token: token,
            baseURL: baseURL,
            platform: platform,
            appVersion: appVersion,
            build: build,
            session: .shared
        )
    }

    init(
        defaults: UserDefaults,
        token: String?,
        baseURL: String?,
        platform: String,
        appVersion: String,
        build: String,
        session: URLSession = .shared
    ) {
        self.defaults = defaults
        self.token = token
        self.baseURL = baseURL
        self.platform = platform
        self.appVersion = appVersion
        self.build = build
        self.session = session

        if let existing = defaults.string(forKey: Self.installIdKey) {
            self.installId = existing
        } else {
            let newId = UUID().uuidString
            defaults.set(newId, forKey: Self.installIdKey)
            self.installId = newId
        }
    }

    func logFetchOutcome(endpoint: String, httpStatus: Int, latencyMs: Int, cacheStatus: String?) {
        let event = TelemetryEvent(
            ts: Self.isoNow(),
            installId: installId,
            platform: platform,
            appVersion: appVersion,
            build: build,
            kind: "fetch_outcome",
            endpoint: endpoint,
            httpStatus: httpStatus,
            latencyMs: latencyMs,
            errorKind: nil,
            cacheStatus: cacheStatus
        )
        logger.info("fetch_outcome \(endpoint, privacy: .public) status=\(httpStatus) latency=\(latencyMs)ms")
        enqueue(event)
    }

    func logFetchError(endpoint: String, errorKind: String, httpStatus: Int?, latencyMs: Int) {
        let event = TelemetryEvent(
            ts: Self.isoNow(),
            installId: installId,
            platform: platform,
            appVersion: appVersion,
            build: build,
            kind: "fetch_error",
            endpoint: endpoint,
            httpStatus: httpStatus,
            latencyMs: latencyMs,
            errorKind: errorKind,
            cacheStatus: nil
        )
        logger.error("fetch_error \(endpoint, privacy: .public) kind=\(errorKind, privacy: .public) status=\(httpStatus.map(String.init) ?? "nil", privacy: .public)")
        enqueue(event)
    }

    func flush() {
        queue.async { [weak self] in self?.flushLocked() }
    }

    private func enqueue(_ event: TelemetryEvent) {
        guard isEnabled else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(event)
            if self.buffer.count > Self.bufferCap {
                self.buffer.removeFirst(self.buffer.count - Self.bufferCap)
            }
            self.scheduleDebouncedFlush()
        }
    }

    private func scheduleDebouncedFlush() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushLocked() }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + Self.debounceSeconds, execute: work)
    }

    private func flushLocked() {
        guard isEnabled, !flushInFlight, !buffer.isEmpty else { return }
        guard let url = URL(string: "\(baseURL!)/log") else { return }
        let snapshot = buffer
        flushInFlight = true

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-App-Token")

        let body: Data
        do {
            body = try JSONEncoder().encode(["events": snapshot])
        } catch {
            logger.error("telemetry encode failed: \(error.localizedDescription, privacy: .public)")
            flushInFlight = false
            return
        }
        request.httpBody = body

        let session = self.session
        let logger = self.logger
        let onComplete: (Bool) -> Void = { [weak self] success in
            guard let self else { return }
            self.queue.async {
                if success {
                    self.buffer.removeFirst(min(snapshot.count, self.buffer.count))
                }
                self.flushInFlight = false
            }
        }

        Task.detached {
            do {
                let (_, response) = try await session.data(for: request)
                let ok = (response as? HTTPURLResponse)?.statusCode == 204
                if !ok {
                    logger.error("telemetry POST returned non-204")
                }
                onComplete(ok)
            } catch {
                logger.error("telemetry POST failed: \(error.localizedDescription, privacy: .public)")
                onComplete(false)
            }
        }
    }

    private static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

extension Telemetry {
    var bufferedEventsForTesting: [TelemetryEvent] {
        queue.sync { buffer }
    }
}
