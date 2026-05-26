import Foundation

public struct OnwardStop: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let arrivalTime: Date
    public let minutesAway: Int
    public let isRealTime: Bool

    public init(id: String, name: String, arrivalTime: Date, isRealTime: Bool = true, now: Date = Date()) {
        self.id = id
        self.name = name
        self.arrivalTime = arrivalTime
        self.isRealTime = isRealTime
        self.minutesAway = max(0, Int(arrivalTime.timeIntervalSince(now) / 60))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try  c.decode(String.self, forKey: .id)
        name        = try  c.decode(String.self, forKey: .name)
        arrivalTime = try  c.decode(Date.self,   forKey: .arrivalTime)
        minutesAway = try  c.decode(Int.self,    forKey: .minutesAway)
        isRealTime  = (try? c.decodeIfPresent(Bool.self, forKey: .isRealTime)) ?? true
    }

    public var minutesString: String {
        if minutesAway == 0 { return "Due" }
        if minutesAway == 1 { return "1 min" }
        return "\(minutesAway) min"
    }

    public var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrivalTime)
    }
}
