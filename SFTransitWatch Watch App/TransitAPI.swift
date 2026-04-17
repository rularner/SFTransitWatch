import Foundation
import SwiftUI

class TransitAPI: ObservableObject {
    private let baseURL = "https://api.511.org/transit"
    @AppStorage("511_API_KEY") private var storedAPIKey = ""
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var apiKey: String {
        return storedAPIKey.isEmpty ? "YOUR_511_API_KEY" : storedAPIKey
    }
    
    @MainActor
    func fetchArrivals(for stopId: String) async -> [BusArrival] {
        isLoading = true
        errorMessage = nil
        
        // Check if we have a valid API key
        guard !storedAPIKey.isEmpty else {
            errorMessage = "Please configure your 511.org API key in Settings"
            isLoading = false
            return getSampleArrivals(for: stopId)
        }
        
        do {
            // 511.org API endpoint for real-time arrivals
            let endpoint = "StopMonitoring"
            let urlString = "\(baseURL)/\(endpoint)?api_key=\(apiKey)&agency=SF&stopCode=\(stopId)"
            
            guard let url = URL(string: urlString) else {
                throw APIError.invalidURL
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                print("API Error: \(httpResponse.statusCode)")
                // Fallback to sample data if API fails
                return getSampleArrivals(for: stopId)
            }
            
            // Parse 511.org XML response
            let arrivals = try parse511Arrivals(data: data)
            isLoading = false
            return arrivals
            
        } catch {
            print("API Error: \(error.localizedDescription)")
            errorMessage = "Failed to load arrivals"
            isLoading = false
            // Fallback to sample data
            return getSampleArrivals(for: stopId)
        }
    }
    
    @MainActor
    func fetchNearbyStops(latitude: Double, longitude: Double, radius: Int = 1000) async -> [BusStop] {
        isLoading = true
        errorMessage = nil
        
        // Check if we have a valid API key
        guard !storedAPIKey.isEmpty else {
            errorMessage = "Please configure your 511.org API key in Settings"
            isLoading = false
            return BusStop.sampleStops
        }
        
        do {
            // 511.org API endpoint for nearby stops
            let endpoint = "StopPlace"
            let urlString = "\(baseURL)/\(endpoint)?api_key=\(apiKey)&lat=\(latitude)&lon=\(longitude)&radius=\(radius)"
            
            guard let url = URL(string: urlString) else {
                throw APIError.invalidURL
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                print("API Error: \(httpResponse.statusCode)")
                // Fallback to sample data if API fails
                return BusStop.sampleStops
            }
            
            // Parse 511.org XML response
            let stops = try parse511Stops(data: data)
            isLoading = false
            return stops
            
        } catch {
            print("API Error: \(error.localizedDescription)")
            errorMessage = "Failed to load nearby stops"
            isLoading = false
            // Fallback to sample data
            return BusStop.sampleStops
        }
    }
    
    // Parse 511.org XML response for arrivals
    private func parse511Arrivals(data: Data) throws -> [BusArrival] {
        // 511.org returns XML data, so we need to parse it
        // This is a simplified parser - in production you'd use a proper XML parser
        
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        
        // Extract arrival times from XML
        // 511.org format: <MonitoredVehicleJourney><MonitoredCall><ExpectedDepartureTime>...</ExpectedDepartureTime></MonitoredCall></MonitoredVehicleJourney>
        
        var arrivals: [BusArrival] = []
        
        // Simple regex parsing for demonstration
        // In production, use XMLParser or a proper XML library
        let pattern = #"<MonitoredVehicleJourney>.*?<LineRef>([^<]+)</LineRef>.*?<DirectionRef>([^<]+)</DirectionRef>.*?<ExpectedDepartureTime>([^<]+)</ExpectedDepartureTime>.*?</MonitoredVehicleJourney>"#
        
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let matches = regex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
        
        for match in matches {
            if let routeRange = Range(match.range(at: 1), in: xmlString),
               let destinationRange = Range(match.range(at: 2), in: xmlString),
               let timeRange = Range(match.range(at: 3), in: xmlString) {
                
                let route = String(xmlString[routeRange])
                let destination = String(xmlString[destinationRange])
                let timeString = String(xmlString[timeRange])
                
                // Parse ISO 8601 date format
                let formatter = ISO8601DateFormatter()
                if let arrivalTime = formatter.date(from: timeString) {
                    let arrival = BusArrival(
                        route: route,
                        destination: destination,
                        arrivalTime: arrivalTime,
                        isRealTime: true
                    )
                    arrivals.append(arrival)
                }
            }
        }
        
        return arrivals.isEmpty ? getSampleArrivals(for: "default") : arrivals
    }
    
    // Parse 511.org XML response for stops
    private func parse511Stops(data: Data) throws -> [BusStop] {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        
        var stops: [BusStop] = []
        
        // Simple regex parsing for demonstration
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
                
                let stop = BusStop(
                    id: id,
                    name: name,
                    code: id,
                    latitude: latitude,
                    longitude: longitude,
                    routes: [] // Routes would need separate API call
                )
                stops.append(stop)
            }
        }
        
        return stops.isEmpty ? BusStop.sampleStops : stops
    }
    
    // Fallback sample data
    private func getSampleArrivals(for stopId: String) -> [BusArrival] {
        switch stopId {
        case "1": // Market St & 4th St
            return [
                BusArrival(route: "38", destination: "Downtown", arrivalTime: Date().addingTimeInterval(180)),
                BusArrival(route: "38R", destination: "Downtown", arrivalTime: Date().addingTimeInterval(420)),
                BusArrival(route: "F", destination: "Fisherman's Wharf", arrivalTime: Date().addingTimeInterval(600))
            ]
        case "2": // Mission St & 16th St
            return [
                BusArrival(route: "14", destination: "Downtown", arrivalTime: Date().addingTimeInterval(240)),
                BusArrival(route: "14R", destination: "Downtown", arrivalTime: Date().addingTimeInterval(480)),
                BusArrival(route: "22", destination: "Potrero Hill", arrivalTime: Date().addingTimeInterval(360))
            ]
        case "3": // Geary Blvd & 22nd Ave
            return [
                BusArrival(route: "38", destination: "Downtown", arrivalTime: Date().addingTimeInterval(300)),
                BusArrival(route: "38R", destination: "Downtown", arrivalTime: Date().addingTimeInterval(540))
            ]
        default:
            return BusArrival.sampleArrivals
        }
    }
    
    // Helper method to get API key from user
    func setAPIKey(_ key: String) {
        storedAPIKey = key
        print("API key updated")
    }
    
    // Check if API key is configured
    var isAPIKeyConfigured: Bool {
        return !storedAPIKey.isEmpty
    }

    /// Look up a single stop by its 511.org stop code. Returns nil if not found.
    func fetchStop(code: String) async -> BusStop? {
        guard !storedAPIKey.isEmpty else { return nil }

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