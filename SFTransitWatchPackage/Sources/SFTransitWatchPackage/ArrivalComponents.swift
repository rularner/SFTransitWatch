import SwiftUI

// MARK: - Route Filter Pill

public struct RouteFilterPill: View {
    public let label: String
    public let isSelected: Bool
    public let action: () -> Void

    public init(label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
#if os(watchOS)
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue : Color.blue.opacity(0.15))
                .foregroundColor(isSelected ? .white : .blue)
                .cornerRadius(8)
#else
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .secondary)
                .clipShape(Capsule())
#endif
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label == "All" ? "All routes" : "Route \(label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "Tap to clear filter" : "Tap to filter arrivals")
    }
}

// MARK: - Arrival Row

public struct BusArrivalRow: View {
    public let arrival: BusArrival

    public init(arrival: BusArrival) {
        self.arrival = arrival
    }

    public var body: some View {
        HStack {
            Text(arrival.route)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .frame(width: 40, height: 40)
                .background(routeColor(for: arrival.route))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.destination)
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    Text(arrival.minutesString)
                        .font(.subheadline)
                        .foregroundColor(arrival.minutesAway <= 2 ? .red : arrival.minutesAway <= 5 ? .orange : .primary)
                        .fontWeight(.semibold)

                    if !arrival.isRealTime {
                        Text("Scheduled")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(arrival.timeString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if arrival.isRealTime {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let timing = arrival.isRealTime ? "real time" : "scheduled"
        return "Route \(arrival.route) to \(arrival.destination), \(arrival.minutesString), \(timing)"
    }

    private func routeColor(for route: String) -> Color {
        if let metro = metroLineColor(for: route) { return metro }
        let fallback: [Color] = [.blue, .green, .orange, .purple, .red, .teal]
        return fallback[abs(route.hashValue) % fallback.count]
    }

    private func metroLineColor(for route: String) -> Color? {
        switch route.uppercased() {
        case "F":        return Color(red: 0.73, green: 0.20, blue: 0.05) // F Market
        case "J":        return Color(red: 0.55, green: 0.35, blue: 0.17) // J Church
        case "K", "KT": return Color(red: 0.43, green: 0.20, blue: 0.56) // K Ingleside / KT
        case "L":        return Color(red: 0.47, green: 0.47, blue: 0.47) // L Taraval
        case "M":        return Color(red: 0.15, green: 0.55, blue: 0.25) // M Ocean View
        case "N":        return Color(red: 0.00, green: 0.35, blue: 0.62) // N Judah
        case "T":        return Color(red: 0.78, green: 0.13, blue: 0.18) // T Third
        case "S":        return Color(red: 0.95, green: 0.62, blue: 0.07) // S Shuttle
        default:         return nil
        }
    }
}
