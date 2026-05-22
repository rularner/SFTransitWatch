import Foundation
import SwiftUI
import SFTransitWatchPackage

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}


@MainActor
class TransitAPI: ObservableObject {
    private let defaultBaseURL = "https://api.511.org/transit"
    @AppStorage("511_API_KEY_FROM_PHONE") private var phoneAPIKey = ""

    @Published var isLoading = false
    @Published var errorMessage: String?
    var urlSession: URLSessionProtocol = URLSession.shared


    private var useDirectFallback = false

    init() {}

    private var resolvedKey: String {
        return phoneAPIKey.isEmpty ? ConfigurationManager.shared.apiKey : phoneAPIKey
    }

    private var hasUsableKey: Bool {
        return !phoneAPIKey.isEmpty || !ConfigurationManager.shared.apiKey.isEmpty
    }

    private var isDirect511Mode: Bool {
        return useDirectFallback || ConfigurationManager.shared.workerToken.isEmpty || ConfigurationManager.shared.workerBaseURL.isEmpty
    }

    private var baseURL: String {
        return isDirect511Mode ? defaultBaseURL : ConfigurationManager.shared.workerBaseURL
    }

    private var apiKey: String {
        return resolvedKey.isEmpty ? "YOUR_511_API_KEY" : resolvedKey
    }

    private var appToken: String? {
        return isDirect511Mode ? nil : ConfigurationManager.shared.workerToken
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

    func fetchArrivals(for stopId: String, agency: String = "SF") async -> [BusArrival] {
        // SnapshotMode: bypass network when launched with -SNAPSHOT_MODE.
        // SnapshotMode.arrivals(for:) currently always returns Castro Station's 4 arrivals
        // regardless of the stop arg. That's intentional for the App Store snapshot.
        if SnapshotMode.isActive {
            return SnapshotMode.arrivals(for: SnapshotMode.sampleStop)
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if isDirect511Mode && !hasUsableKey {
            errorMessage = "Please configure your 511.org API key in Settings"
            return []
        }

        let endpoint = "StopMonitoring"
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        var queryItems = [
            URLQueryItem(name: "agency", value: agency),
            URLQueryItem(name: "stopCode", value: stopId)
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
            let (data, response) = try await self.urlSession.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: latencyMs)
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode == 401, !isDirect511Mode {
                useDirectFallback = true
                Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "worker_401_fallback", httpStatus: 401, latencyMs: latencyMs)
                return await fetchArrivals(for: stopId, agency: agency)
            }

            if httpResponse.statusCode != 200 {
                Telemetry.shared.logFetchError(
                    endpoint: endpoint,
                    errorKind: errorKind(for: APIError.invalidResponse, status: httpResponse.statusCode),
                    httpStatus: httpResponse.statusCode,
                    latencyMs: latencyMs
                )
                errorMessage = "511.org returned HTTP \(httpResponse.statusCode)"
                return []
            }

            let cacheStatus = httpResponse.value(forHTTPHeaderField: "X-Cache-Status")
            Telemetry.shared.logFetchOutcome(endpoint: endpoint, httpStatus: 200, latencyMs: latencyMs, cacheStatus: cacheStatus)
            let realTimeArrivals = try parse511Arrivals(data: data)
            if realTimeArrivals.isEmpty {
                return await fetchScheduledDepartures(for: stopId, agency: agency)
            }
            return realTimeArrivals
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: errorKind(for: error, status: nil), httpStatus: nil, latencyMs: latencyMs)
            errorMessage = "Failed to load arrivals: \(error.localizedDescription)"
            return []
        }
    }
    
    func fetchScheduledDepartures(for stopId: String, agency: String) async -> [BusArrival] {
        let endpoint = "StopTimetable"
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        var queryItems = [
            URLQueryItem(name: "operatorref", value: agency),
            URLQueryItem(name: "monitoringref", value: stopId)
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
            let cacheStatus = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache-Status")
            Telemetry.shared.logFetchOutcome(endpoint: endpoint, httpStatus: 200, latencyMs: latencyMs, cacheStatus: cacheStatus)
            return TransitJSON.decodeScheduledDepartures(data) ?? []
        } catch {
            return []
        }
    }

    /// Fans out the StopPlace lookup across each enabled agency in parallel
    /// and merges the results, tagging every returned stop with its agency.
    /// Sets errorMessage when all agencies fail or some are degraded.
    func fetchNearbyStops(latitude: Double, longitude: Double, radius: Int = 1000, agencies: [String] = ["SF"]) async -> [BusStop] {
        // SnapshotMode: bypass network when launched with -SNAPSHOT_MODE.
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

        let queryAgencies = agencies.isEmpty ? ["SF"] : agencies

        let outcomes: [Result<[BusStop], Error>] = await withTaskGroup(of: Result<[BusStop], Error>.self) { group in
            for agency in queryAgencies {
                group.addTask { [self] in
                    do {
                        let stops = try await self.fetchNearbyStops(latitude: latitude, longitude: longitude, radius: radius, agency: agency)
                        return .success(stops)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<[BusStop], Error>] = []
            for await outcome in group { collected.append(outcome) }
            return collected
        }

        var merged: [BusStop] = []
        var failureCount = 0
        for outcome in outcomes {
            switch outcome {
            case .success(let stops): merged.append(contentsOf: stops)
            case .failure: failureCount += 1
            }
        }

        if failureCount == queryAgencies.count {
            errorMessage = "Couldn't reach 511.org for any agency"
        } else if failureCount > 0 {
            errorMessage = "Some agencies unavailable"
        } else if merged.isEmpty {
            errorMessage = "No nearby stops found"
        }

        return merged
    }

    /// Single-agency StopPlace lookup. Throws on any failure (logged to
    /// telemetry); the caller is expected to merge with other agencies'
    /// results.
    private func fetchNearbyStops(latitude: Double, longitude: Double, radius: Int, agency: String) async throws -> [BusStop] {
        let endpoint = "Stops"
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        var queryItems = [
            URLQueryItem(name: "operator_id", value: agency),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            // 511.org deployments differ on expected coordinate keys.
            // Send both forms so geofiltering works consistently.
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "radius", value: String(radius))
        ]
        if isDirect511Mode {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: 0)
            throw APIError.invalidURL
        }
        let request = makeRequest(url: url)

        let started = Date()
        let (data, response) = try await self.urlSession.data(for: request)
        let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: latencyMs)
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401, !isDirect511Mode {
            useDirectFallback = true
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "worker_401_fallback", httpStatus: 401, latencyMs: latencyMs)
            return await fetchNearbyStops(latitude: latitude, longitude: longitude, radius: radius, agencies: [agency])
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
        return try parse511Stops(data: data, agency: agency)
    }
    
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
                destination: destination,
                arrivalTime: arrivalTime,
                isRealTime: true,
                alerts: alerts
            )
        }
    }

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

    // Helper method to set API key
    func setAPIKey(_ key: String) {
        ConfigurationManager.shared.apiKey = key
        print("API key updated")
    }
    
    // Check if API key is configured
    var isAPIKeyConfigured: Bool {
        // SnapshotMode: pretend the key is configured so settings/onboarding views
        // render their post-configuration state in App Store screenshots.
        if SnapshotMode.isActive { return true }
        return hasUsableKey
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

    func searchStops(query: String, agencies: [String]) async -> [BusStop]? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !agencies.isEmpty else { return [] }
        if SnapshotMode.isActive { return [] }
        if isDirect511Mode && !hasUsableKey { return [] }

        var successCount = 0
        var all: [BusStop] = []

        await withTaskGroup(of: (stops: [BusStop]?, succeeded: Bool).self) { group in
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
}
