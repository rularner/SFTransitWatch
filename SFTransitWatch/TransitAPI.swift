import Foundation
import SwiftUI

class TransitAPI: ObservableObject {
    private let defaultBaseURL = "https://api.511.org/transit"
    private var baseURL: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "TRANSIT_API_BASE_URL") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }
        return defaultBaseURL
    }
    @AppStorage("511_API_KEY") private var storedAPIKey = ""
    @AppStorage("511_API_KEY_FROM_PHONE") private var phoneAPIKey = ""

    @Published var isLoading = false
    @Published var errorMessage: String?

    private var resolvedKey: String {
        return phoneAPIKey.isEmpty ? storedAPIKey : phoneAPIKey
    }

    private var hasUsableKey: Bool {
        return !phoneAPIKey.isEmpty || !storedAPIKey.isEmpty
    }

    private var isDirect511Mode: Bool {
        return baseURL.contains("api.511.org")
    }

    private var apiKey: String {
        return resolvedKey.isEmpty ? "YOUR_511_API_KEY" : resolvedKey
    }

    private var appToken: String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "APP_TOKEN") as? String) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func makeRequest(url: URL) -> URLRequest? {
        var request = URLRequest(url: url)
        if !isDirect511Mode {
            guard let token = appToken else { return nil }
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
        guard let request = makeRequest(url: url) else {
            errorMessage = "App token not configured. See README."
            return []
        }

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: latencyMs)
                throw APIError.invalidResponse
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
    
    func fetchNearbyStops(latitude: Double, longitude: Double, radius: Int = 1000, agencies: [String] = ["SF"]) async -> [BusStop] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if isDirect511Mode && !hasUsableKey {
            errorMessage = "Please configure your 511.org API key in Settings"
            return []
        }

        let agency = agencies.first ?? "SF"
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
            errorMessage = "Failed to load nearby stops: invalid URL"
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: 0)
            return []
        }
        guard let request = makeRequest(url: url) else {
            errorMessage = "App token not configured. See README."
            return []
        }

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: "network", httpStatus: nil, latencyMs: latencyMs)
                throw APIError.invalidResponse
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
            let stops = try parse511Stops(data: data, agency: agency)
            if stops.isEmpty {
                errorMessage = "No nearby stops found"
            }
            return stops
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            Telemetry.shared.logFetchError(endpoint: endpoint, errorKind: errorKind(for: error, status: nil), httpStatus: nil, latencyMs: latencyMs)
            errorMessage = "Failed to load nearby stops: \(error.localizedDescription)"
            return []
        }
    }
    
    // Parse 511.org XML response for arrivals
    private func parse511Arrivals(data: Data) throws -> [BusArrival] {
        // 511 currently serves JSON for StopMonitoring, but we keep XML fallback
        // for compatibility with worker/legacy responses.
        if let jsonArrivals = parseJSONArrivals(data: data), !jsonArrivals.isEmpty {
            return jsonArrivals
        }
        return try parseXMLArrivals(data: data)
    }

    private func parseJSONArrivals(data: Data) -> [BusArrival]? {
        guard let payload = try? JSONDecoder().decode(StopMonitoringResponse.self, from: data) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        return payload.serviceDelivery.stopMonitoringDelivery.monitoredStopVisit.compactMap { visit in
            let journey = visit.monitoredVehicleJourney
            let call = journey.monitoredCall
            let rawTime =
                call.expectedArrivalTime ??
                call.expectedDepartureTime ??
                call.aimedArrivalTime ??
                call.aimedDepartureTime
            guard
                let rawTime,
                let arrivalTime = formatter.date(from: rawTime)
            else { return nil }
            return BusArrival(
                route: journey.lineRef,
                destination: journey.directionRef,
                arrivalTime: arrivalTime,
                isRealTime: true
            )
        }
    }

    private func parseXMLArrivals(data: Data) throws -> [BusArrival] {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        var arrivals: [BusArrival] = []
        let pattern = #"<MonitoredVehicleJourney>.*?<LineRef>([^<]+)</LineRef>.*?<DirectionRef>([^<]+)</DirectionRef>.*?<(?:ExpectedArrivalTime|ExpectedDepartureTime|AimedArrivalTime|AimedDepartureTime)>([^<]+)</(?:ExpectedArrivalTime|ExpectedDepartureTime|AimedArrivalTime|AimedDepartureTime)>.*?</MonitoredVehicleJourney>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let matches = regex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
        let formatter = ISO8601DateFormatter()
        for match in matches {
            if let routeRange = Range(match.range(at: 1), in: xmlString),
               let destinationRange = Range(match.range(at: 2), in: xmlString),
               let timeRange = Range(match.range(at: 3), in: xmlString) {
                let route = String(xmlString[routeRange])
                let destination = String(xmlString[destinationRange])
                let timeString = String(xmlString[timeRange])
                if let arrivalTime = formatter.date(from: timeString) {
                    arrivals.append(BusArrival(
                        route: route,
                        destination: destination,
                        arrivalTime: arrivalTime,
                        isRealTime: true
                    ))
                }
            }
        }
        return arrivals
    }
    
    // Parse 511.org XML response for stops
    private func parse511Stops(data: Data, agency: String = "SF") throws -> [BusStop] {
        // Direct 511 Stops endpoint returns JSON. Worker/legacy paths may still
        // return XML StopPlace payloads, so we attempt JSON first then fall back.
        if let jsonStops = parseJSONStops(data: data, agency: agency), !jsonStops.isEmpty {
            return jsonStops
        }
        return try parseXMLStops(data: data, agency: agency)
    }

    private func parseJSONStops(data: Data, agency: String) -> [BusStop]? {
        guard let payload = try? JSONDecoder().decode(StopsResponse.self, from: data) else {
            return nil
        }
        return payload.contents.dataObjects.scheduledStopPoints.compactMap { point in
            guard
                let latitude = Double(point.location.latitude),
                let longitude = Double(point.location.longitude)
            else { return nil }
            return BusStop(
                id: point.id,
                name: point.name,
                code: point.id,
                latitude: latitude,
                longitude: longitude,
                routes: [],
                agency: agency
            )
        }
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
    
    // Helper method to get API key from user
    func setAPIKey(_ key: String) {
        storedAPIKey = key
        print("API key updated")
    }
    
    // Check if API key is configured
    var isAPIKeyConfigured: Bool {
        return hasUsableKey
    }
}

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case decodingError
    case networkError
    case xmlParsingError
}

private struct StopsResponse: Decodable {
    let contents: StopsContents

    enum CodingKeys: String, CodingKey {
        case contents = "Contents"
    }
}

private struct StopsContents: Decodable {
    let dataObjects: StopsDataObjects
}

private struct StopsDataObjects: Decodable {
    let scheduledStopPoints: [ScheduledStopPoint]

    enum CodingKeys: String, CodingKey {
        case scheduledStopPoints = "ScheduledStopPoint"
    }
}

private struct ScheduledStopPoint: Decodable {
    let id: String
    let name: String
    let location: StopLocation

    enum CodingKeys: String, CodingKey {
        case id
        case name = "Name"
        case location = "Location"
    }
}

private struct StopLocation: Decodable {
    let longitude: String
    let latitude: String

    enum CodingKeys: String, CodingKey {
        case longitude = "Longitude"
        case latitude = "Latitude"
    }
}

private struct StopMonitoringResponse: Decodable {
    let serviceDelivery: StopMonitoringServiceDelivery

    enum CodingKeys: String, CodingKey {
        case serviceDelivery = "ServiceDelivery"
    }
}

private struct StopMonitoringServiceDelivery: Decodable {
    let stopMonitoringDelivery: StopMonitoringDelivery

    enum CodingKeys: String, CodingKey {
        case stopMonitoringDelivery = "StopMonitoringDelivery"
    }
}

private struct StopMonitoringDelivery: Decodable {
    let monitoredStopVisit: [MonitoredStopVisit]

    enum CodingKeys: String, CodingKey {
        case monitoredStopVisit = "MonitoredStopVisit"
    }
}

private struct MonitoredStopVisit: Decodable {
    let monitoredVehicleJourney: MonitoredVehicleJourney

    enum CodingKeys: String, CodingKey {
        case monitoredVehicleJourney = "MonitoredVehicleJourney"
    }
}

private struct MonitoredVehicleJourney: Decodable {
    let lineRef: String
    let directionRef: String
    let monitoredCall: MonitoredCall

    enum CodingKeys: String, CodingKey {
        case lineRef = "LineRef"
        case directionRef = "DirectionRef"
        case monitoredCall = "MonitoredCall"
    }
}

private struct MonitoredCall: Decodable {
    let expectedArrivalTime: String?
    let expectedDepartureTime: String?
    let aimedArrivalTime: String?
    let aimedDepartureTime: String?

    enum CodingKeys: String, CodingKey {
        case expectedArrivalTime = "ExpectedArrivalTime"
        case expectedDepartureTime = "ExpectedDepartureTime"
        case aimedArrivalTime = "AimedArrivalTime"
        case aimedDepartureTime = "AimedDepartureTime"
    }
}