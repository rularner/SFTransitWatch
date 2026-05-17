import Foundation

public struct BusArrival: Identifiable, Codable, Sendable {
    public var id = UUID()
    public let route: String
    public let destination: String
    public let arrivalTime: Date
    public let minutesAway: Int
    public let isRealTime: Bool

    public init(route: String, destination: String, arrivalTime: Date, isRealTime: Bool = true, now: Date = Date()) {
        self.route = route
        self.destination = destination
        self.arrivalTime = arrivalTime
        self.isRealTime = isRealTime

        let timeInterval = arrivalTime.timeIntervalSince(now)
        self.minutesAway = max(0, Int(timeInterval / 60))
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
