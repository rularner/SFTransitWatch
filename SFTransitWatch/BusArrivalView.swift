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
    @StateObject private var commutePrompt = CommutePromptState()
    @StateObject private var countdown = RefreshCountdown(interval: 30)
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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

            FavoriteToggleButton(stop: stop, favoritesManager: favoritesManager, slotsManager: slotsManager, commutePrompt: commutePrompt)
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
                        if stop.hasValidLocation {
                            stopLocationView
                                .frame(width: 160)
                        }
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

                if stop.hasValidLocation {
                    Section {
                        stopLocationView
                            .listRowBackground(Color.clear)
                    }
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
                    if let banner = transitAPI.softBanner {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.secondary)
                            Text(banner).font(.caption).foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(banner)
                        .listRowBackground(Color.clear)
                    }
                    ForEach(filteredArrivals) { arrival in
                        NavigationLink(destination: BusJourneyView(
                            arrival: arrival,
                            originStopId: stop.id,
                            agency: stop.agency
                        )) {
                            BusArrivalRow(arrival: arrival)
                        }
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
        .onDisappear {
            locationManager.stopLocationUpdates()
        }
        .onReceive(ticker) { _ in
            guard !transitAPI.isLoading else { return }
            if countdown.tick() {
                Task { await loadArrivals() }
            }
        }
        .onReceive(transitAPI.$pollInterval) { newInterval in
            countdown.setInterval(Int(newInterval))
        }
        .commutePrompt(commutePrompt, stopId: stop.id, stopName: stop.name, slotsManager: slotsManager)
    }

    private func loadArrivals() async {
        arrivals = await transitAPI.fetchArrivals(for: stop.id, agency: stop.agency)
        lastUpdated = Date()
        countdown.reset()
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
