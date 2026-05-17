import SwiftUI
import WatchKit
import SFTransitWatchPackage

struct BusArrivalView: View {
    let stop: BusStop
    @StateObject private var transitAPI = TransitAPI()
    @EnvironmentObject var favoritesManager: FavoritesManager
    @EnvironmentObject var slotsManager: CommuteSlotsManager

    @StateObject private var locationManager = LocationManager()
    @State private var selectedTab = 0
    @State private var arrivals: [BusArrival] = []
    @State private var lastUpdated = Date()
    @State private var secondsUntilRefresh = 30
    @State private var notifiedArrivalIDs: Set<UUID> = []
    @State private var selectedRoute: String? = nil
    @State private var showCommutePrompt = false
    @State private var commuteEmptySlots: [CommuteSlotsManager.Slot] = []

    init(
        stop: BusStop,
        transitAPI: TransitAPI? = nil,
        initialArrivals: [BusArrival] = [],
        initialTab: Int = 0
    ) {
        self.stop = stop
        _transitAPI = StateObject(wrappedValue: transitAPI ?? TransitAPI())
        _arrivals = State(initialValue: initialArrivals)
        _selectedTab = State(initialValue: initialTab)
    }

    private let refreshInterval = 30

    var filteredArrivals: [BusArrival] { arrivals.filtered(by: selectedRoute) }
    var uniqueRoutes: [String] { arrivals.uniqueRoutes }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Arrivals Pane
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

                let alerts = arrivals.uniqueAlerts
                if !alerts.isEmpty {
                    Section(header: Text("Service Alerts")) {
                        ForEach(alerts, id: \.self) { alert in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption2)
                                Text(alert)
                                    .font(.caption2)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Service alert: \(alert)")
                        }
                    }
                }

                // Arrivals
                Section {
                    if transitAPI.isLoading && arrivals.isEmpty {
                        HStack {
                            ProgressView()
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
                        ForEach(filteredArrivals) { arrival in
                            BusArrivalRow(arrival: arrival)
                        }
                    }
                } header: {
                    HStack {
                        Text("Next Arrivals")
                        Spacer()
                        if transitAPI.isLoading {
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
                guard !transitAPI.isLoading else { return }
                if secondsUntilRefresh <= 1 {
                    secondsUntilRefresh = refreshInterval
                    Task { await loadArrivals() }
                } else {
                    secondsUntilRefresh -= 1
                }
            }
            .tag(0)

            // MARK: - Location Pane
            VStack {
                StopLocationView(
                    stop: stop,
                    currentLocation: locationManager.currentLocation,
                    currentHeading: locationManager.currentHeading,
                    isHeadingEnabled: locationManager.isLocationEnabled
                )
                    .padding()
            }
            .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .onAppear {
            locationManager.startLocationUpdates()
            Task {
                await loadArrivals()
            }
        }
        .onReceive(Timer.publish(every: TimeInterval(refreshInterval), on: .main, in: .common).autoconnect()) { _ in
            Task {
                await loadArrivals()
            }
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
        secondsUntilRefresh = refreshInterval

        fireHapticsIfNeeded()

        if let first = arrivals.first {
            ComplicationUpdater.update(
                stopId: stop.id,
                stopName: stop.name,
                route: first.route,
                minutesAway: first.minutesAway,
                slotsManager: slotsManager
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

#if DEBUG
#Preview {
    NavigationStack {
        BusArrivalView(stop: BusStop.previewStops[0])
            .environmentObject(FavoritesManager())
            .environmentObject(CommuteSlotsManager())
    }
}
#endif
