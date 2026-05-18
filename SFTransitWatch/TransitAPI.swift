import Foundation

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

import SwiftUI
import SFTransitWatchPackage

class TransitAPI: ObservableObject {
    private let defaultBaseURL = "https://api.511.org/transit"
    // Key synced from the phone to the watch via WatchConnectivity — lives in .standard.
    @AppStorage("511_API_KEY_FROM_PHONE") private var phoneAPIKey = ""

    @Published var isLoading = false
    @Published var errorMessage: String?

    private var useDirectFallback = false

    var urlSession: URLSessionProtocol = URLSession.shared

    private var resolvedKey: String {
        phoneAPIKey.isEmpty ? ConfigurationManager.shared.apiKey : phoneAPIKey
    }

    private var hasUsableKey: Bool {
        if SnapshotMode.isActive { return true }
        return !phoneAPIKey.isEmpty || !ConfigurationManager.shared.apiKey.isEmpty
    }

    private var isDirect511Mode: Bool {
        return useDirectFallback
            || ConfigurationManager.shared.workerToken.isEmpty
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
            let (data, response) = try await urlSession.data(for: request)
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
            return try parse511Arrivals(data: data)
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: errorKind(for: error, status: nil), httpStatus: nil, latencyMs: latencyMs)
            errorMessage = "Failed to load arrivals: \(error.localizedDescription)"
            return []
        }
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

        if allStops.isEmpty {
            errorMessage = "No nearby stops found"
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
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        var queryItems = [
            URLQueryItem(name: "operator_id", value: agencyCode),
            URLQueryItem(name: "lat",         value: String(latitude)),
            URLQueryItem(name: "lon",         value: String(longitude)),
            URLQueryItem(name: "latitude",    value: String(latitude)),
            URLQueryItem(name: "longitude",   value: String(longitude)),
            URLQueryItem(name: "radius",      value: String(radius))
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
        return try parseXMLArrivals(data: data)
    }

    private func parseXMLArrivals(data: Data) throws -> [BusArrival] {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        let alerts = TransitJSON.parseSituationSummaries(from: data)
        var arrivals: [BusArrival] = []
        let pattern = #"<MonitoredVehicleJourney>.*?<LineRef>([^<]+)</LineRef>.*?<DirectionRef>([^<]+)</DirectionRef>.*?<(?:ExpectedArrivalTime|ExpectedDepartureTime|AimedArrivalTime|AimedDepartureTime)>([^<]+)</(?:ExpectedArrivalTime|ExpectedDepartureTime|AimedArrivalTime|AimedDepartureTime)>.*?</MonitoredVehicleJourney>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let matches = regex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
        let formatter = ISO8601DateFormatter()
        for match in matches {
            if let routeRange = Range(match.range(at: 1), in: xmlString),
               let destinationRange = Range(match.range(at: 2), in: xmlString),
               let timeRange = Range(match.range(at: 3), in: xmlString) {
                let route = TransitJSON.cleanLineRef(String(xmlString[routeRange]))
                let destination = String(xmlString[destinationRange])
                let timeString = String(xmlString[timeRange])
                if let arrivalTime = formatter.date(from: timeString) {
                    arrivals.append(BusArrival(
                        route: route,
                        destination: destination,
                        arrivalTime: arrivalTime,
                        isRealTime: true,
                        alerts: alerts
                    ))
                }
            }
        }
        return arrivals
    }

    
    // Parse 511.org XML response for stops
    private func parse511Stops(data: Data, agency: String = "SF") throws -> [BusStop] {
        if let jsonStops = TransitJSON.decodeStops(data, agency: agency), !jsonStops.isEmpty {
            return jsonStops
        }
        Telemetry.shared.logFetchError(endpoint: "Stops", errorKind: "json_parse_fallback", httpStatus: nil, latencyMs: 0)
        return try parseXMLStops(data: data, agency: agency)
    }

    private func parseXMLStops(data: Data, agency: String) throws -> [BusStop] {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        var stops: [BusStop] = []
        let pattern = #"<StopPlace>.*?<StopPlaceRef>([^<]+)</StopPlaceRef>.*?<StopPlaceName>([^<]+)</StopPlaceName>.*?<Location>.*?<Latitude>([^<]+)</Latitude>.*?<Longitude>([^<]+)</Longitude>.*?</Location>.*?</StopPlace>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let matches = regex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
        for match in matches {
            if let idRange = Range(match.range(at: 1), in: xmlString),
               let nameRange = Range(match.range(at: 2), in: xmlString),
               let latRange = Range(match.range(at: 3), in: xmlString),
               let lonRange = Range(match.range(at: 4), in: xmlString) {
                let id = String(xmlString[idRange])
                let name = String(xmlString[nameRange])
                let latitude = Double(xmlString[latRange]) ?? 0.0
                let longitude = Double(xmlString[lonRange]) ?? 0.0
                stops.append(BusStop(
                    id: id,
                    name: name,
                    code: id,
                    latitude: latitude,
                    longitude: longitude,
                    routes: [],
                    agency: agency
                ))
            }
        }
        return stops
    }
    
    func setAPIKey(_ key: String) {
        ConfigurationManager.shared.apiKey = key
    }
    
    // Check if API key is configured
    var isAPIKeyConfigured: Bool {
        // SnapshotMode: pretend the key is configured so settings/onboarding views
        // render their post-configuration state in App Store screenshots.
        if SnapshotMode.isActive { return true }
        return hasUsableKey
    }
}
