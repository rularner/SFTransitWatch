import Foundation
import SwiftUI

class TransitAPI: ObservableObject {
    private let baseURL = "https://api.511.org/transit"
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

    private var apiKey: String {
        return resolvedKey.isEmpty ? "YOUR_511_API_KEY" : resolvedKey
    }
    
    @MainActor
    func fetchArrivals(for stopId: String) async -> [BusArrival] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard hasUsableKey else {
            errorMessage = "Please configure your 511.org API key in Settings"
            return []
        }

        do {
            let endpoint = "StopMonitoring"
            let urlString = "\(baseURL)/\(endpoint)?api_key=\(apiKey)&agency=SF&stopCode=\(stopId)"

            guard let url = URL(string: urlString) else {
                throw APIError.invalidURL
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                errorMessage = "511.org returned HTTP \(httpResponse.statusCode)"
                return []
            }

            return try parse511Arrivals(data: data)
        } catch {
            errorMessage = "Failed to load arrivals: \(error.localizedDescription)"
            return []
        }
    }
    
    @MainActor
    func fetchNearbyStops(latitude: Double, longitude: Double, radius: Int = 1000) async -> [BusStop] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard hasUsableKey else {
            errorMessage = "Please configure your 511.org API key in Settings"
            return []
        }

        do {
            let endpoint = "StopPlace"
            let urlString = "\(baseURL)/\(endpoint)?api_key=\(apiKey)&lat=\(latitude)&lon=\(longitude)&radius=\(radius)"

            guard let url = URL(string: urlString) else {
                throw APIError.invalidURL
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                errorMessage = "511.org returned HTTP \(httpResponse.statusCode)"
                return []
            }

            return try parse511Stops(data: data)
        } catch {
            errorMessage = "Failed to load nearby stops: \(error.localizedDescription)"
            return []
        }
    }
    
    private func parse511Arrivals(data: Data) throws -> [BusArrival] {
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
                route: route,
                destination: destination,
                arrivalTime: arrivalTime,
                isRealTime: true
            )
        }
    }

    private func parse511Stops(data: Data) throws -> [BusStop] {
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
                routes: []
            )
        }
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

    /// Look up a single stop by its 511.org stop code. Returns nil if not found.
    func fetchStop(code: String) async -> BusStop? {
        guard hasUsableKey else { return nil }

        let urlString = "\(baseURL)/StopPlace?api_key=\(apiKey)&stopCode=\(code)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let stops = try parse511Stops(data: data)
            return stops.first
        } catch {
            return nil
        }
    }
}

// MARK: - Testing helpers (internal access for unit tests)

extension TransitAPI {
    func parseArrivalsForTesting(data: Data) throws -> [BusArrival] {
        return try parse511Arrivals(data: data)
    }

    func parseStopsForTesting(data: Data) throws -> [BusStop] {
        return try parse511Stops(data: data)
    }
}

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case decodingError
    case networkError
    case xmlParsingError
} 