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
    
    func fetchArrivals(for stopId: String) async -> [BusArrival] {
        isLoading = true
        errorMessage = nil
        
        // In direct mode we need a user key, but worker-proxy mode does not.
        if isDirect511Mode && !hasUsableKey {
            errorMessage = "Please configure your 511.org API key in Settings"
            isLoading = false
            return getSampleArrivals(for: stopId)
        }
        
        do {
            // 511.org API endpoint for real-time arrivals
            let endpoint = "StopMonitoring"
            var components = URLComponents(string: "\(baseURL)/\(endpoint)")
            var queryItems = [
                URLQueryItem(name: "agency", value: "SF"),
                URLQueryItem(name: "stopCode", value: stopId)
            ]
            if isDirect511Mode {
                queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
            }
            components?.queryItems = queryItems
            
            guard let url = components?.url else {
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
    
    func fetchNearbyStops(latitude: Double, longitude: Double, radius: Int = 1000) async -> [BusStop] {
        isLoading = true
        errorMessage = nil
        
        if isDirect511Mode && !hasUsableKey {
            errorMessage = "Please configure your 511.org API key in Settings"
            isLoading = false
            return BusStop.sampleStops
        }
        
        do {
            // 511.org API endpoint for nearby stops
            let endpoint = "StopPlace"
            var components = URLComponents(string: "\(baseURL)/\(endpoint)")
            var queryItems = [
                URLQueryItem(name: "lat", value: String(latitude)),
                URLQueryItem(name: "lon", value: String(longitude)),
                URLQueryItem(name: "radius", value: String(radius))
            ]
            if isDirect511Mode {
                queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
            }
            components?.queryItems = queryItems
            
            guard let url = components?.url else {
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