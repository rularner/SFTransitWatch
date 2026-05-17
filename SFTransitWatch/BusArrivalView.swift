import SwiftUI
import SFTransitWatchPackage

struct BusArrivalView: View {
    let stop: BusStop
    @StateObject private var transitAPI = TransitAPI()
    @EnvironmentObject var favoritesManager: FavoritesManager
    @EnvironmentObject var slotsManager: CommuteSlotsManager
    @StateObject private var locationManager = LocationManager()
    @State private var arrivals: [BusArrival] = []
    @State private var lastUpdated = Date()
    @State private var selectedRoute: String? = nil
    @State private var showCommutePrompt = false
    @State private var commuteEmptySlots: [CommuteSlotsManager.Slot] = []

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var filteredArrivals: [BusArrival] { arrivals.filtered(by: selectedRoute) }

    @ViewBuilder
    private var stopInfoContent: some View {
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
                let isAdding = !favoritesManager.isFavorite(stop.id)
                favoritesManager.toggleFavorite(stop)
                if isAdding {
                    let empty = CommuteSlotsManager.Slot.allCases.filter { slotsManager.stopId(for: $0) == nil }
                    if !empty.isEmpty {
                        commuteEmptySlots = empty
                        showCommutePrompt = true
                    }
                }
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

    @ViewBuilder
    private var stopLocationView: some View {
        StopLocationView(
            stop: stop,
            currentLocation: locationManager.currentLocation,
            currentHeading: locationManager.currentHeading,
            isHeadingEnabled: locationManager.isLocationEnabled
        )
    }

    var body: some View {
        List {
            if isLandscape {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            stopInfoContent
                        }
                        stopLocationView
                            .frame(width: 160)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        stopInfoContent
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    stopLocationView
                        .listRowBackground(Color.clear)
                }
            }

            let alerts = arrivals.uniqueAlerts
            if !alerts.isEmpty {
                Section {
                    ForEach(alerts, id: \.self) { alert in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(alert)
                                .font(.caption)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Service alert: \(alert)")
                    }
                } header: {
                    Text("Service Alerts")
                }
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
        .confirmationDialog(
            "Add to commute?",
            isPresented: $showCommutePrompt
        ) {
            if commuteEmptySlots.contains(.morning) {
                Button("Morning Commute") { slotsManager.setStopId(stop.id, for: .morning) }
            }
            if commuteEmptySlots.contains(.afternoon) {
                Button("Afternoon Commute") { slotsManager.setStopId(stop.id, for: .afternoon) }
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Use \"\(stop.name)\" as a commute stop?")
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

#if DEBUG
#Preview {
    NavigationStack {
        BusArrivalView(stop: BusStop.previewStops[0])
            .environmentObject(FavoritesManager())
            .environmentObject(CommuteSlotsManager())
    }
}
#endif
