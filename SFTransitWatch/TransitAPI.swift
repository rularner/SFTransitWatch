import Foundation

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

import SwiftUI
import SFTransitWatchPackage

class TransitAPI: ObservableObject {
    private let defaultBaseURL = default511BaseURL
    // Key synced from the phone to the watch via WatchConnectivity — lives in .standard.
    @AppStorage("511_API_KEY_FROM_PHONE") private var phoneAPIKey = ""
    @AppStorage("511_API_KEY", store: UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName))
    private var localAPIKey = ""
    @AppStorage("WORKER_TOKEN", store: UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName))
    private var workerToken = ""

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pollInterval: TimeInterval = 30
    @Published var softBanner: String?

    private var useDirectFallback = false
    private let basePollInterval: TimeInterval = 30
    private let maxPollInterval: TimeInterval = 300
    private let keepLastMaxAge: TimeInterval = 120
    private var consecutive429 = 0

    var urlSession: URLSessionProtocol = URLSession.shared
    var stopRoutesCache = StopRoutesCache()
    var now: () -> Date = { Date() }
    private let throttleInterval: TimeInterval = 20
    private struct CachedArrivals { let arrivals: [BusArrival]; let timestamp: Date }
    private var arrivalsCache: [String: CachedArrivals] = [:]
    private var inFlight: [String: Task<[BusArrival], Never>] = [:]

    private struct CachedSchedule { let arrivals: [BusArrival]; let timestamp: Date }
    // StopTimetable is a mostly-static schedule (valid ~24h) — caching it client-side means
    // repeated empty/failed StopMonitoring polls during a GTFS-RT gap fall back to this cache
    // instead of re-hitting the network every poll.
    private var scheduleCache: [String: CachedSchedule] = [:]
    private let scheduleCacheTTL: TimeInterval = 24 * 60 * 60

    private func arrivalsCacheKey(_ stopId: String, _ agency: String) -> String { "\(agency):\(stopId)" }

    private var resolvedKey: String {
        phoneAPIKey.isEmpty ? localAPIKey : phoneAPIKey
    }

    private var hasUsableKey: Bool {
        if SnapshotMode.isActive { return true }
        return !phoneAPIKey.isEmpty || !localAPIKey.isEmpty
    }

    private var isDirect511Mode: Bool {
        return useDirectFallback
            || workerToken.isEmpty
            || ConfigurationManager.shared.workerBaseURL.isEmpty
    }

    private var baseURL: String {
        isDirect511Mode ? defaultBaseURL : ConfigurationManager.shared.workerBaseURL
    }

    private var apiKey: String {
        resolvedKey.isEmpty ? "YOUR_511_API_KEY" : resolvedKey
    }

    private var appToken: String? {
        isDirect511Mode ? nil : ConfigurationManager.shared.workerToken
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if !isDirect511Mode, let token = appToken {
            request.setValue(token, forHTTPHeaderField: "X-App-Token")
        }
        return request
    }

    private func errorKind(for error: Error, status: Int?) -> String {
        if let status {
            if status == 401 { return "missing_key" }
            if (400...499).contains(status) { return "http_4xx" }
            if (500...599).contains(status) { return "http_5xx" }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return "network"
            default:
                break
            }
        }
        if case .xmlParsingError? = error as? APIError { return "parse" }
        return "network"
    }

    @MainActor
    func fetchArrivals(for stopId: String, agency: String = "SF") async -> [BusArrival] {
        if SnapshotMode.isActive { return SnapshotMode.arrivals(for: SnapshotMode.sampleStop) }
        let key = arrivalsCacheKey(stopId, agency)
        if let cached = arrivalsCache[key], now().timeIntervalSince(cached.timestamp) < throttleInterval {
            return cached.arrivals
        }
        if let existing = inFlight[key] {
            return await existing.value
        }
        let task = Task { @MainActor in await self.performFetchArrivals(for: stopId, agency: agency) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func applyBackoff(retryAfter: String?) {
        consecutive429 += 1
        if let retryAfter, let seconds = TimeInterval(retryAfter), seconds > 0 {
            // Clamp to at least the base interval: a small Retry-After must never make us
            // poll *faster* than normal while we're being rate-limited.
            pollInterval = min(max(seconds, basePollInterval), maxPollInterval)
            return
        }
        let raw = basePollInterval * pow(2.0, Double(consecutive429))   // 60, 120, 240, …
        let jitter = Double.random(in: 0...5)
        pollInterval = min(raw, maxPollInterval) + jitter
    }

    private func resetBackoff() {
        consecutive429 = 0
        pollInterval = basePollInterval
        softBanner = nil
    }

    @MainActor
    private func performFetchArrivals(for stopId: String, agency: String) async -> [BusArrival] {
        isLoading = true
        errorMessage = nil
        softBanner = nil
        defer { isLoading = false }

        if isDirect511Mode && !hasUsableKey {
            errorMessage = "Please configure your 511.org API key in Settings"
            return []
        }

        let endpoint = "StopMonitoring"
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        var queryItems = [
            URLQueryItem(name: "agency", value: agency),
            URLQueryItem(name: "stopCode", value: stopId),
            URLQueryItem(name: "MaximumNumberOfCallsOnwards", value: "10"),
            URLQueryItem(name: "format", value: "json")
        ]
        if isDirect511Mode {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            errorMessage = "Failed to load arrivals: invalid URL"
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: 0)
            return []
        }
        let request = makeRequest(url: url)

        let started = Date()
        do {
            let (data, response) = try await urlSession.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: latencyMs)
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode == 401, !isDirect511Mode {
                useDirectFallback = true
                Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "worker_401_fallback", httpStatus: 401, latencyMs: latencyMs)
                return await performFetchArrivals(for: stopId, agency: agency)
            }

            if httpResponse.statusCode != 200 {
                Telemetry.shared.logFetchError(
                    endpoint: endpoint,
                    errorKind: errorKind(for: APIError.invalidResponse, status: httpResponse.statusCode),
                    httpStatus: httpResponse.statusCode,
                    latencyMs: latencyMs
                )
                if httpResponse.statusCode == 429 {
                    applyBackoff(retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After"))
                }
                return await recentOrScheduledFallback(stopId: stopId, agency: agency, errorDescription: "511.org returned HTTP \(httpResponse.statusCode)")
            }

            let cacheStatus = httpResponse.value(forHTTPHeaderField: "X-Cache-Status")
            Telemetry.shared.logFetchOutcome(endpoint: endpoint, httpStatus: 200, latencyMs: latencyMs, cacheStatus: cacheStatus)
            let realTimeArrivals = try parse511Arrivals(data: data)
            if realTimeArrivals.isEmpty {
                let scheduled = await fetchScheduledDepartures(for: stopId, agency: agency)
                arrivalsCache[arrivalsCacheKey(stopId, agency)] = CachedArrivals(arrivals: scheduled, timestamp: now())
                resetBackoff()
                if cacheStatus == "ERROR" {
                    softBanner = "Live updates unavailable — showing scheduled times"
                }
                return scheduled
            }
            arrivalsCache[arrivalsCacheKey(stopId, agency)] = CachedArrivals(arrivals: realTimeArrivals, timestamp: now())
            resetBackoff()
            return realTimeArrivals
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: errorKind(for: error, status: nil), httpStatus: nil, latencyMs: latencyMs)
            return await recentOrScheduledFallback(stopId: stopId, agency: agency, errorDescription: "Failed to load arrivals: \(error.localizedDescription)")
        }
    }

    /// Shared by the non-200 and thrown-error paths above: prefer recent kept-last real-time
    /// data, then the (cached) schedule, before giving up and surfacing `errorDescription`.
    private func recentOrScheduledFallback(stopId: String, agency: String, errorDescription: String) async -> [BusArrival] {
        let key = arrivalsCacheKey(stopId, agency)
        if let cached = arrivalsCache[key], now().timeIntervalSince(cached.timestamp) < keepLastMaxAge, !cached.arrivals.isEmpty {
            errorMessage = nil
            softBanner = "Live updates paused"
            return cached.arrivals
        }
        let scheduled = await fetchScheduledDepartures(for: stopId, agency: agency)
        if !scheduled.isEmpty {
            arrivalsCache[key] = CachedArrivals(arrivals: scheduled, timestamp: now())
            errorMessage = nil
            softBanner = "Showing scheduled times"
            return scheduled
        }
        errorMessage = errorDescription
        return []
    }

    func fetchScheduledDepartures(for stopId: String, agency: String) async -> [BusArrival] {
        let key = arrivalsCacheKey(stopId, agency)
        if let cached = scheduleCache[key], now().timeIntervalSince(cached.timestamp) < scheduleCacheTTL {
            return refreshScheduledTimestamps(cached.arrivals)
        }

        let endpoint = "StopTimetable"
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        var queryItems = [
            URLQueryItem(name: "operatorref", value: agency),
            URLQueryItem(name: "monitoringref", value: stopId),
            URLQueryItem(name: "format", value: "json")
        ]
        if isDirect511Mode {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }
        let request = makeRequest(url: url)
        let started = Date()
        do {
            let (data, response) = try await urlSession.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let cacheStatus = http.value(forHTTPHeaderField: "X-Cache-Status")
            Telemetry.shared.logFetchOutcome(endpoint: endpoint, httpStatus: 200, latencyMs: latencyMs, cacheStatus: cacheStatus)
            let decoded = TransitJSON.decodeScheduledDepartures(data) ?? []
            if !decoded.isEmpty {
                scheduleCache[key] = CachedSchedule(arrivals: decoded, timestamp: now())
            }
            return decoded
        } catch {
            return []
        }
    }

    /// Cached schedule entries carry `minutesAway`/`timeString`-relevant state baked in from
    /// when they were first decoded (see `BusArrival.init`) — recompute it against the current
    /// time on every cache hit so a long-lived cache entry doesn't show a frozen countdown.
    private func refreshScheduledTimestamps(_ arrivals: [BusArrival]) -> [BusArrival] {
        let current = now()
        return arrivals.map {
            BusArrival(
                route: $0.route,
                destination: $0.destination,
                arrivalTime: $0.arrivalTime,
                isRealTime: $0.isRealTime,
                alerts: $0.alerts,
                vehicleRef: $0.vehicleRef,
                onwardStops: $0.onwardStops,
                now: current
            )
        }
    }

    /// Returns the distinct, sorted set of routes serving a stop, derived
    /// from `/StopTimetable` (mostly-static scheduled data) and cached
    /// on-device for 7 days so direct-511.org users don't refetch on every
    /// list load.
    func fetchRoutes(for stopId: String, agency: String) async -> [String] {
        if let cached = stopRoutesCache.routes(for: stopId, agency: agency) {
            return cached
        }
        let arrivals = await fetchScheduledDepartures(for: stopId, agency: agency)
        let routes = Array(Set(arrivals.map(\.route))).sorted()
        stopRoutesCache.setRoutes(routes, for: stopId, agency: agency)
        return routes
    }

    @MainActor
    func fetchNearbyStops(latitude: Double, longitude: Double, radius: Int = 1000, agencies: [String] = ["SF"]) async -> [BusStop] {
        if SnapshotMode.isActive {
            return SnapshotMode.nearbyStops
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if isDirect511Mode && !hasUsableKey {
            errorMessage = "Please configure your 511.org API key in Settings"
            return []
        }

        var allStops: [BusStop] = []
        for agency in agencies {
            do {
                let stops = try await fetchStopsForOneAgency(agency, latitude: latitude, longitude: longitude, radius: radius)
                allStops.append(contentsOf: stops)
            } catch {
                Telemetry.shared.logFetchError(endpoint: "Stops", errorKind: errorKind(for: error, status: nil), httpStatus: nil, latencyMs: 0)
            }
        }

        return allStops
    }
    
    @MainActor
    private func fetchStopsForOneAgency(
        _ agencyCode: String,
        latitude: Double,
        longitude: Double,
        radius: Int
    ) async throws -> [BusStop] {
        let endpoint = "Stops"
        let effectiveRadius = max(radius, Agency.named(agencyCode)?.nearbyRadius ?? radius)
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        var queryItems = [
            URLQueryItem(name: "operator_id", value: agencyCode),
            URLQueryItem(name: "lat",         value: String(latitude)),
            URLQueryItem(name: "lon",         value: String(longitude)),
            URLQueryItem(name: "latitude",    value: String(latitude)),
            URLQueryItem(name: "longitude",   value: String(longitude)),
            URLQueryItem(name: "radius",      value: String(effectiveRadius))
        ]
        if isDirect511Mode {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: 0)
            throw APIError.invalidResponse
        }
        let request = makeRequest(url: url)
        let started = Date()

        let (data, response) = try await urlSession.data(for: request)
        let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: latencyMs)
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401, !isDirect511Mode {
            useDirectFallback = true
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "worker_401_fallback", httpStatus: 401, latencyMs: latencyMs)
            return try await fetchStopsForOneAgency(agencyCode, latitude: latitude, longitude: longitude, radius: radius)
        }

        if httpResponse.statusCode != 200 {
            Telemetry.shared.logFetchError(
                endpoint: endpoint,
                errorKind: errorKind(for: APIError.invalidResponse, status: httpResponse.statusCode),
                httpStatus: httpResponse.statusCode,
                latencyMs: latencyMs
            )
            throw APIError.invalidResponse
        }

        let cacheStatus = httpResponse.value(forHTTPHeaderField: "X-Cache-Status")
        Telemetry.shared.logFetchOutcome(endpoint: endpoint, httpStatus: 200, latencyMs: latencyMs, cacheStatus: cacheStatus)
        return try parse511Stops(data: data, agency: agencyCode)
    }

    // Parse 511.org XML response for arrivals
    private func parse511Arrivals(data: Data) throws -> [BusArrival] {
        if let jsonArrivals = TransitJSON.decodeArrivals(data), !jsonArrivals.isEmpty {
            return jsonArrivals
        }
        Telemetry.shared.logFetchError(endpoint: "StopMonitoring", errorKind: "json_parse_fallback", httpStatus: nil, latencyMs: 0)

        let alerts = TransitJSON.parseSituationSummaries(from: data)

        let formatter = ISO8601DateFormatter()
        let records = SIRIXMLParser.parseRecords(
            data: data,
            entryElement: "MonitoredVehicleJourney",
            fields: ["LineRef", "DirectionRef", "ExpectedDepartureTime"]
        )
        return records.compactMap { record in
            guard
                let route = record["LineRef"],
                let destination = record["DirectionRef"],
                let timeString = record["ExpectedDepartureTime"],
                let arrivalTime = formatter.date(from: timeString)
            else { return nil }
            return BusArrival(
                route: TransitJSON.cleanLineRef(route),
                destination: TransitJSON.directionLabel(destination, lineRef: route),
                arrivalTime: arrivalTime,
                isRealTime: true,
                alerts: alerts
            )
        }
    }

    // Parse 511.org XML response for stops
    private func parse511Stops(data: Data, agency: String = "SF") throws -> [BusStop] {
        if let jsonStops = TransitJSON.decodeStops(data, agency: agency), !jsonStops.isEmpty {
            return jsonStops
        }
        Telemetry.shared.logFetchError(endpoint: "Stops", errorKind: "json_parse_fallback", httpStatus: nil, latencyMs: 0)

        let records = SIRIXMLParser.parseRecords(
            data: data,
            entryElement: "StopPlace",
            fields: ["StopPlaceRef", "StopPlaceName", "Latitude", "Longitude"]
        )
        return records.compactMap { record in
            guard
                let id = record["StopPlaceRef"],
                let name = record["StopPlaceName"],
                let latString = record["Latitude"], let latitude = Double(latString),
                let lonString = record["Longitude"], let longitude = Double(lonString)
            else { return nil }
            return BusStop(
                id: id,
                name: name,
                code: id,
                latitude: latitude,
                longitude: longitude,
                routes: [],
                agency: agency
            )
        }
    }
    
    private func fetchAllStops(agency: String) async throws -> [BusStop] {
        let endpoint = "Stops"
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        var queryItems = [URLQueryItem(name: "operator_id", value: agency)]
        if isDirect511Mode {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw APIError.invalidResponse }
        let request = makeRequest(url: url)

        let started = Date()
        let (data, response) = try await urlSession.data(for: request)
        let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
        guard let http = response as? HTTPURLResponse else {
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network",
                                           httpStatus: nil, latencyMs: latencyMs)
            throw APIError.invalidResponse
        }
        if http.statusCode != 200 {
            Telemetry.shared.logFetchError(endpoint: endpoint,
                                           errorKind: errorKind(for: APIError.invalidResponse, status: http.statusCode),
                                           httpStatus: http.statusCode, latencyMs: latencyMs)
            throw APIError.invalidResponse
        }
        let cacheStatus = http.value(forHTTPHeaderField: "X-Cache-Status")
        Telemetry.shared.logFetchOutcome(endpoint: endpoint, httpStatus: 200,
                                         latencyMs: latencyMs, cacheStatus: cacheStatus)
        return try parse511Stops(data: data, agency: agency)
    }

    func fetchJourneyStops(
        route: String,
        destination: String,
        boardingStopId: String,
        boardingTime: Date,
        agency: String
    ) async -> [OnwardStop] {
        let endpoint = "Timetable"
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        var queryItems = [
            URLQueryItem(name: "operator_id", value: agency),
            URLQueryItem(name: "line_id", value: route),
            URLQueryItem(name: "format", value: "json")
        ]
        if isDirect511Mode {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }
        let request = makeRequest(url: url)
        let started = Date()
        do {
            let (data, response) = try await urlSession.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let cacheStatus = http.value(forHTTPHeaderField: "X-Cache-Status")
            Telemetry.shared.logFetchOutcome(endpoint: endpoint, httpStatus: 200, latencyMs: latencyMs, cacheStatus: cacheStatus)
            return TransitJSON.decodeTimetableJourneyStops(
                data: data,
                boardingStopId: boardingStopId,
                boardingTime: boardingTime
            ) ?? []
        } catch {
            return []
        }
    }

    func searchStops(query: String, agencies: [String]) async -> [BusStop]? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !agencies.isEmpty else { return [] }
        if SnapshotMode.isActive { return [] }
        if isDirect511Mode && !hasUsableKey { return [] }

        var successCount = 0
        var all: [BusStop] = []

        await withTaskGroup(of: (stops: [BusStop]?, succeeded: Bool).self) { [self] group in
            for agency in agencies {
                group.addTask {
                    if let stops = try? await self.fetchAllStops(agency: agency) {
                        return (stops, true)
                    }
                    return (nil, false)
                }
            }
            for await result in group {
                if result.succeeded { successCount += 1 }
                if let stops = result.stops {
                    all.append(contentsOf: stops.filter { stop in
                        stop.code == trimmed || stop.id == trimmed ||
                        stop.name.localizedCaseInsensitiveContains(trimmed)
                    })
                }
            }
        }

        guard successCount > 0 else { return nil }
        var seen = Set<String>()
        return all.filter { seen.insert("\($0.id)|\($0.agency)").inserted }
    }

    func setAPIKey(_ key: String) {
        ConfigurationManager.shared.apiKey = key
    }
    
    // Check if API key is configured
    var isAPIKeyConfigured: Bool {
        if SnapshotMode.isActive { return true }
        return hasUsableKey || !workerToken.isEmpty
    }
}
