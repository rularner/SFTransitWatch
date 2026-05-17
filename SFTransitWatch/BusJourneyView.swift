import SwiftUI
import SFTransitWatchPackage

struct BusJourneyView: View {
    let arrival: BusArrival
    let originStopId: String
    let agency: String

    var body: some View {
        List {
            if arrival.onwardStops.isEmpty {
                emptyState
            } else {
                ForEach(arrival.onwardStops) { stop in
                    NavigationLink(destination: BusArrivalView(stop: busStop(from: stop))) {
                        JourneyStopRow(stop: stop, isOrigin: stop.id == originStopId)
                    }
                }
            }
        }
        .navigationTitle("Route \(arrival.route) → \(arrival.destination)")
    }

    private func busStop(from stop: OnwardStop) -> BusStop {
        BusStop(
            id: stop.id,
            name: stop.name,
            code: stop.id,
            latitude: 0,
            longitude: 0,
            routes: [],
            agency: agency
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bus")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text("Journey details not available for this vehicle")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .listRowBackground(Color.clear)
    }
}

struct JourneyStopRow: View {
    let stop: OnwardStop
    let isOrigin: Bool

    var body: some View {
        HStack {
            if isOrigin {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }

            Text(stop.name)
                .font(.headline)
                .foregroundColor(isOrigin ? .blue : .primary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(stop.minutesString)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(minuteColor)

                Text(stop.timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var minuteColor: Color {
        if stop.minutesAway <= 2 { return .red }
        if stop.minutesAway <= 5 { return .orange }
        return .primary
    }

    private var accessibilityLabel: String {
        let location = isOrigin ? "current stop, " : ""
        return "\(location)\(stop.name), \(stop.minutesString)"
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BusJourneyView(
            arrival: BusArrival(
                route: "38",
                destination: "Downtown",
                arrivalTime: Date().addingTimeInterval(300),
                onwardStops: [
                    OnwardStop(id: "15725", name: "Market St & 4th St",
                               arrivalTime: Date().addingTimeInterval(300)),
                    OnwardStop(id: "15726", name: "Market St & 5th St",
                               arrivalTime: Date().addingTimeInterval(480)),
                    OnwardStop(id: "15727", name: "Market St & 7th St",
                               arrivalTime: Date().addingTimeInterval(600)),
                ]
            ),
            originStopId: "15725",
            agency: "SF"
        )
        .environmentObject(FavoritesManager())
        .environmentObject(CommuteSlotsManager())
    }
}
#endif
