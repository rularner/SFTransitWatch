import SwiftUI
import SFTransitWatchPackage

struct BusArrivalView: View {
    let stop: BusStop
    @StateObject private var transitAPI = TransitAPI()
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var locationManager = LocationManager()
    @State private var arrivals: [BusArrival] = []
    @State private var lastUpdated = Date()
    @State private var selectedRoute: String? = nil

    private var filteredArrivals: [BusArrival] { arrivals.filtered(by: selectedRoute) }

    var body: some View {
        List {
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

                        Button(action: {
                            favoritesManager.toggleFavorite(for: stop.id)
                        }) {
                            Image(systemName: favoritesManager.isFavorite(stop.id) ? "star.fill" : "star")
                                .foregroundColor(favoritesManager.isFavorite(stop.id) ? .yellow : .gray)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if !arrivals.uniqueRoutes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                RouteFilterPill(label: "All", isSelected: selectedRoute == nil) {
                                    selectedRoute = nil
                                }
                                ForEach(arrivals.uniqueRoutes, id: \.self) { route in
                                    RouteFilterPill(label: route, isSelected: selectedRoute == route) {
                                        selectedRoute = selectedRoute == route ? nil : route
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                StopLocationView(
                    stop: stop,
                    currentLocation: locationManager.currentLocation,
                    currentHeading: locationManager.currentHeading,
                    isHeadingEnabled: locationManager.isLocationEnabled
                )
                .listRowBackground(Color.clear)
            }

            Section {
                if transitAPI.isLoading && arrivals.isEmpty {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Loading arrivals...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                } else if let error = transitAPI.errorMessage, arrivals.isEmpty {
                    ErrorStateView(message: error) {
                        Task { await loadArrivals() }
                    }
                    .listRowBackground(Color.clear)
                } else if filteredArrivals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bus")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                        Text(arrivals.isEmpty ? "No upcoming arrivals" : "No \(selectedRoute ?? "") arrivals")
                            .font(.headline)
                        Text("Check back later for updates")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    if let error = transitAPI.errorMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Error: \(error)")
                        .listRowBackground(Color.clear)
                    }
                    ForEach(filteredArrivals) { arrival in
                        BusArrivalRow(arrival: arrival)
                    }
                }
            } header: {
                HStack {
                    Text("Next Arrivals")
                    Spacer()
                    if !transitAPI.isLoading {
                        Text("Updated \(formatTime(lastUpdated))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Arrivals")
        .refreshable {
            await loadArrivals()
        }
        .onAppear {
            locationManager.startLocationUpdates()
            Task { await loadArrivals() }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task { await loadArrivals() }
        }
    }

    private func loadArrivals() async {
        arrivals = await transitAPI.fetchArrivals(for: stop.id, agency: stop.agency)
        lastUpdated = Date()
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .secondary)
                .clipShape(Capsule())
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
        case "F": return Color(red: 0.73, green: 0.20, blue: 0.05)
        case "J": return Color(red: 0.55, green: 0.35, blue: 0.17)
        case "K", "KT": return Color(red: 0.43, green: 0.20, blue: 0.56)
        case "L": return Color(red: 0.47, green: 0.47, blue: 0.47)
        case "M": return Color(red: 0.15, green: 0.55, blue: 0.25)
        case "N": return Color(red: 0.00, green: 0.35, blue: 0.62)
        case "T": return Color(red: 0.78, green: 0.13, blue: 0.18)
        case "S": return Color(red: 0.95, green: 0.62, blue: 0.07)
        default: return nil
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BusArrivalView(stop: BusStop.previewStops[0])
    }
}
#endif
