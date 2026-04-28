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
    /// 511.org agency code (e.g. "SF" for Muni, "BA" for BART).
    /// Stop codes are scoped per-agency, so this is needed for arrival fetches.
    let agency: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    init(id: String, name: String, code: String, latitude: Double, longitude: Double, routes: [String] = [], isFavorite: Bool = false, agency: String = "SF") {
        self.id = id
        self.name = name
        self.code = code
        self.latitude = latitude
        self.longitude = longitude
        self.routes = routes
        self.isFavorite = isFavorite
        self.agency = agency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.code = try c.decode(String.self, forKey: .code)
        self.latitude = try c.decode(Double.self, forKey: .latitude)
        self.longitude = try c.decode(Double.self, forKey: .longitude)
        self.routes = try c.decodeIfPresent([String].self, forKey: .routes) ?? []
        self.isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        // Older persisted stops predate agency; default to Muni.
        self.agency = try c.decodeIfPresent(String.self, forKey: .agency) ?? "SF"
    }

    func distance(to location: CLLocation) -> CLLocationDistance {
        return self.location.distance(from: location)
    }
}

#if DEBUG
extension BusStop {
    static let previewStops: [BusStop] = [
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
#endif