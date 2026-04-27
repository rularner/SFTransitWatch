import Foundation

struct BusArrival: Identifiable, Codable {
    var id = UUID()
    let route: String
    let destination: String
    let arrivalTime: Date
    let minutesAway: Int
    let isRealTime: Bool
    
    init(route: String, destination: String, arrivalTime: Date, isRealTime: Bool = true, now: Date = Date()) {
        self.route = route
        self.destination = destination
        self.arrivalTime = arrivalTime
        self.isRealTime = isRealTime

        let timeInterval = arrivalTime.timeIntervalSince(now)
        self.minutesAway = max(0, Int(timeInterval / 60))
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrivalTime)
    }
    
    var minutesString: String {
        if minutesAway == 0 {
            return "Due"
        } else if minutesAway == 1 {
            return "1 min"
        } else {
            return "\(minutesAway) min"
        }
    }
}

extension BusArrival {
    static let sampleArrivals = [
        BusArrival(
            route: "38",
            destination: "Downtown",
            arrivalTime: Date().addingTimeInterval(300), // 5 minutes
            isRealTime: true
        ),
        BusArrival(
            route: "38R",
            destination: "Downtown",
            arrivalTime: Date().addingTimeInterval(600), // 10 minutes
            isRealTime: true
        ),
        BusArrival(
            route: "F",
            destination: "Fisherman's Wharf",
            arrivalTime: Date().addingTimeInterval(900), // 15 minutes
            isRealTime: false
        )
    ]
} 