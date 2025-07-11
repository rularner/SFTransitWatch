import Foundation
import CoreLocation

struct BusStop: Identifiable, Codable {
    let id: String
    let name: String
    let code: String
    let latitude: Double
    let longitude: Double
    let routes: [String]
    var isFavorite: Bool
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
    
    init(id: String, name: String, code: String, latitude: Double, longitude: Double, routes: [String] = [], isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.code = code
        self.latitude = latitude
        self.longitude = longitude
        self.routes = routes
        self.isFavorite = isFavorite
    }
    
    func distance(to location: CLLocation) -> CLLocationDistance {
        return self.location.distance(from: location)
    }
}

extension BusStop {
    static let sampleStops = [
        BusStop(
            id: "1",
            name: "Market St & 4th St",
            code: "M4",
            latitude: 37.7858,
            longitude: -122.4064,
            routes: ["38", "38R", "F"],
            isFavorite: true
        ),
        BusStop(
            id: "2", 
            name: "Mission St & 16th St",
            code: "M16",
            latitude: 37.7652,
            longitude: -122.4194,
            routes: ["14", "14R", "22"],
            isFavorite: false
        ),
        BusStop(
            id: "3",
            name: "Geary Blvd & 22nd Ave",
            code: "G22", 
            latitude: 37.7231,
            longitude: -122.4792,
            routes: ["38", "38R"],
            isFavorite: true
        )
    ]
} 