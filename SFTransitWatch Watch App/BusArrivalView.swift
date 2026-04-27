import SwiftUI
import WatchKit

struct BusArrivalView: View {
    let stop: BusStop
    @StateObject private var transitAPI = TransitAPI()
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var commuteSlotsManager = CommuteSlotsManager()

    @State private var arrivals: [BusArrival] = []
    @State private var isLoading = false
    @State private var lastUpdated = Date()
    @State private var secondsUntilRefresh = 30
    @State private var notifiedArrivalIDs: Set<UUID> = []
    @State private var selectedRoute: String? = nil  // nil = show all

    private let refreshInterval = 30

    var filteredArrivals: [BusArrival] {
        guard let route = selectedRoute else { return arrivals }
        return arrivals.filter { $0.route == route }
    }

    var uniqueRoutes: [String] {
        var seen = Set<String>()
        return arrivals.compactMap { seen.insert($0.route).inserted ? $0.route : nil }
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(stop.name)
                                .font(.headline)
                            Text("Stop \(stop.code)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: { favoritesManager.toggleFavorite(for: stop.id) }) {
                            Image(systemName: favoritesManager.isFavorite(stop.id) ? "star.fill" : "star")
                                .foregroundColor(favoritesManager.isFavorite(stop.id) ? .yellow : .gray)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(favoritesManager.isFavorite(stop.id) ? "Remove from favorites" : "Add to favorites")
                    }

                    if !stop.routes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                RouteFilterPill(label: "All", isSelected: selectedRoute == nil) {
                                    selectedRoute = nil
                                }
                                ForEach(uniqueRoutes, id: \.self) { route in
                                    RouteFilterPill(label: route, isSelected: selectedRoute == route) {
                                        selectedRoute = selectedRoute == route ? nil : route
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let error = transitAPI.errorMessage {
                Section {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Error: \(error)")
                }
            }

            // Arrivals
            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading arrivals...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                } else if filteredArrivals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bus")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                        Text(arrivals.isEmpty ? "No arrivals scheduled" : "No \(selectedRoute ?? "") arrivals")
                            .font(.headline)
                        Text("Check back later for updates")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredArrivals) { arrival in
                        BusArrivalRow(arrival: arrival)
                    }
                }
            } header: {
                HStack {
                    Text("Next Arrivals")
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("↻ \(secondsUntilRefresh)s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Arrivals")
        .refreshable {
            await loadArrivals()
        }
        .onAppear {
            Task { await loadArrivals() }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard !isLoading else { return }
            if secondsUntilRefresh <= 1 {
                secondsUntilRefresh = refreshInterval
                Task { await loadArrivals() }
            } else {
                secondsUntilRefresh -= 1
            }
        }
    }

    private func loadArrivals() async {
        isLoading = true
        arrivals = await transitAPI.fetchArrivals(for: stop.id, agency: stop.agency)
        lastUpdated = Date()
        secondsUntilRefresh = refreshInterval
        isLoading = false

        fireHapticsIfNeeded()

        if let first = arrivals.first {
            ComplicationUpdater.update(
                stopId: stop.id,
                stopName: stop.name,
                route: first.route,
                minutesAway: first.minutesAway,
                slotsManager: commuteSlotsManager
            )
        }
    }

    private func fireHapticsIfNeeded() {
        for arrival in arrivals where arrival.minutesAway <= 2 {
            guard !notifiedArrivalIDs.contains(arrival.id) else { continue }
            notifiedArrivalIDs.insert(arrival.id)
            WKInterfaceDevice.current().play(.notification)
        }
    }
}

// MARK: - Route Filter Pill

struct RouteFilterPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue : Color.blue.opacity(0.15))
                .foregroundColor(isSelected ? .white : .blue)
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label == "All" ? "All routes" : "Route \(label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "Tap to clear filter" : "Tap to filter arrivals")
    }
}

// MARK: - Arrival Row

struct BusArrivalRow: View {
    let arrival: BusArrival

    var body: some View {
        HStack {
            Text(arrival.route)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
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
                        Text("Sched.")
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
        case "F": return Color(red: 0.73, green: 0.20, blue: 0.05)   // F Market, historic red
        case "J": return Color(red: 0.55, green: 0.35, blue: 0.17)   // J Church, brown
        case "K", "KT": return Color(red: 0.43, green: 0.20, blue: 0.56) // K Ingleside / KT, purple
        case "L": return Color(red: 0.47, green: 0.47, blue: 0.47)   // L Taraval, gray
        case "M": return Color(red: 0.15, green: 0.55, blue: 0.25)   // M Ocean View, green
        case "N": return Color(red: 0.00, green: 0.35, blue: 0.62)   // N Judah, blue
        case "T": return Color(red: 0.78, green: 0.13, blue: 0.18)   // T Third, red
        case "S": return Color(red: 0.95, green: 0.62, blue: 0.07)   // S Shuttle, yellow-orange
        default: return nil
        }
    }
}

#Preview {
    NavigationStack {
        BusArrivalView(stop: BusStop.sampleStops[0])
    }
}
