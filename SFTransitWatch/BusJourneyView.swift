import SwiftUI
import SFTransitWatchPackage

struct BusJourneyView: View {
    let arrival: BusArrival
    let originStopId: String
    let agency: String

    @StateObject private var transitAPI = TransitAPI()
    @State private var scheduledStops: [OnwardStop] = []
    @State private var isLoadingSchedule = false

    private var displayedStops: [OnwardStop] {
        arrival.onwardStops.isEmpty ? scheduledStops : arrival.onwardStops
    }

    private var isScheduled: Bool {
        arrival.onwardStops.isEmpty && !scheduledStops.isEmpty
    }

    var body: some View {
        List {
            if isScheduled {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.clock")
                        .foregroundColor(.secondary)
                    Text("Scheduled times — no real-time tracking")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowBackground(Color.clear)
            }

            if isLoadingSchedule {
                HStack {
                    ProgressView()
                    Text("Loading schedule…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowBackground(Color.clear)
            } else if displayedStops.isEmpty {
                emptyState
            } else {
                ForEach(displayedStops) { stop in
                    NavigationLink(destination: BusArrivalView(stop: busStop(from: stop))) {
                        JourneyStopRow(stop: stop, isOrigin: stop.id == originStopId)
                    }
                }
            }
        }
        .navigationTitle("Route \(arrival.route) → \(arrival.destination)")
        .task {
            if arrival.onwardStops.isEmpty {
                isLoadingSchedule = true
                scheduledStops = await transitAPI.fetchJourneyStops(
                    route: arrival.route,
                    destination: arrival.destination,
                    boardingStopId: originStopId,
                    boardingTime: arrival.arrivalTime,
                    agency: agency
                )
                isLoadingSchedule = false
            }
        }
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
        let timing = stop.isRealTime ? "" : ", scheduled"
        return "\(location)\(stop.name), \(stop.minutesString)\(timing)"
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
