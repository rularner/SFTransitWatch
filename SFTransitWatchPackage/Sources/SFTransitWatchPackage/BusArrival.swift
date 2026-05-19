import Foundation

public struct BusArrival: Identifiable, Codable, Sendable {
    public var id = UUID()
    public let route: String
    public let destination: String
    public let arrivalTime: Date
    public let minutesAway: Int
    public let isRealTime: Bool
    /// Deduplicated service-alert summaries for this arrival's vehicle journey.
    public let alerts: [String]
    public let vehicleRef: String?
    public let onwardStops: [OnwardStop]

    public init(
        route: String,
        destination: String,
        arrivalTime: Date,
        isRealTime: Bool = true,
        alerts: [String] = [],
        vehicleRef: String? = nil,
        onwardStops: [OnwardStop] = [],
        now: Date = Date()
    ) {
        self.route = route
        self.destination = destination
        self.arrivalTime = arrivalTime
        self.isRealTime = isRealTime
        self.alerts = alerts
        self.vehicleRef = vehicleRef
        self.onwardStops = onwardStops
        let timeInterval = arrivalTime.timeIntervalSince(now)
        self.minutesAway = max(0, Int(timeInterval / 60))
    }

    // Custom decoder so older persisted payloads without "alerts" still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = (try? c.decode(UUID.self,   forKey: .id))          ?? UUID()
        route       = try  c.decode(String.self,  forKey: .route)
        destination = try  c.decode(String.self,  forKey: .destination)
        arrivalTime = try  c.decode(Date.self,    forKey: .arrivalTime)
        minutesAway = try  c.decode(Int.self,     forKey: .minutesAway)
        isRealTime  = try  c.decode(Bool.self,    forKey: .isRealTime)
        alerts      = (try? c.decodeIfPresent([String].self,     forKey: .alerts))      ?? []
        vehicleRef  = try? c.decodeIfPresent(String.self,        forKey: .vehicleRef)
        onwardStops = (try? c.decodeIfPresent([OnwardStop].self, forKey: .onwardStops)) ?? []
    }

    public var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrivalTime)
    }

    public var minutesString: String {
        if minutesAway == 0 {
            return "Due"
        } else if minutesAway == 1 {
            return "1 min"
        } else {
            return "\(minutesAway) min"
        }
    }
}

public extension Array where Element == BusArrival {
    func filtered(by route: String?) -> [BusArrival] {
        guard let route else { return self }
        return filter { $0.route == route }
    }

    var uniqueRoutes: [String] {
        var seen = Set<String>()
        return compactMap { seen.insert($0.route).inserted ? $0.route : nil }
    }

    /// Deduplicated service alerts across all arrivals, in first-seen order.
    var uniqueAlerts: [String] {
        var seen = Set<String>()
        return flatMap { $0.alerts }.filter { seen.insert($0).inserted }
    }
}

#if DEBUG
extension BusArrival {
    public static let previewArrivals: [BusArrival] = [
        BusArrival(
            route: "38",
            destination: "Downtown",
            arrivalTime: Date().addingTimeInterval(300),
            isRealTime: true
        ),
        BusArrival(
            route: "38R",
            destination: "Downtown",
            arrivalTime: Date().addingTimeInterval(600),
            isRealTime: true
        ),
        BusArrival(
            route: "F",
            destination: "Fisherman's Wharf",
            arrivalTime: Date().addingTimeInterval(900),
            isRealTime: false
        )
    ]
}
#endif
