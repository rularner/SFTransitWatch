import SwiftUI
import CoreLocation
import SFTransitWatchPackage

struct BusStopListView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var transitAPI = TransitAPI()
    @EnvironmentObject var favoritesManager: FavoritesManager
    @AppStorage(EnabledAgencies.storageKey, store: UserDefaults(suiteName: SharedAgenciesManager.appGroupSuiteName))
    private var enabledAgenciesRaw = EnabledAgencies.default
    @AppStorage(Agency.selectedAgencyKey) private var selectedAgencyRaw: String = ""
    @State private var nearbyStops: [BusStop] = []
    @State private var showingSettingsAlert = false
    @State private var showingStopCodeEntry = false
    @State private var foundStop: BusStop? = nil

    init(
        transitAPI: TransitAPI? = nil,
        locationManager: LocationManager? = nil,
        initialNearbyStops: [BusStop] = []
    ) {
        _transitAPI = StateObject(wrappedValue: transitAPI ?? TransitAPI())
        _locationManager = StateObject(wrappedValue: locationManager ?? LocationManager())
        _nearbyStops = State(initialValue: initialNearbyStops)
    }

    private var enabledAgencies: [String] {
        EnabledAgencies.parse(enabledAgenciesRaw)
    }
    private var activeAgencyFilter: Agency? {
        guard !selectedAgencyRaw.isEmpty else { return nil }
        return Agency.named(selectedAgencyRaw)
    }
    private var queryAgencies: [String] {
        if let filter = activeAgencyFilter {
            return [filter.code]
        }
        return enabledAgencies
    }
    private var showAgencyBadges: Bool {
        queryAgencies.count > 1
    }

    var body: some View {
        List {
            filterBanner
            if !transitAPI.isAPIKeyConfigured {
                apiKeyPromptSection
            } else if transitAPI.isLoading && nearbyStops.isEmpty {
                loadingSection
            } else if let error = transitAPI.errorMessage, nearbyStops.isEmpty {
                Section {
                    ErrorStateView(message: error) {
                        Task { await loadNearbyStops() }
                    }
                    .listRowBackground(Color.clear)
                }
            } else if nearbyStops.isEmpty {
                locationPromptSection
            } else {
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
                stopSections
            }
        }
        .navigationTitle("Nearby Stops")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { showingStopCodeEntry = true }) {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showingStopCodeEntry) {
            StopCodeEntryView(
                transitAPI: transitAPI,
                agencies: EnabledAgencies.parse(enabledAgenciesRaw)
            ) { foundStop in
                self.foundStop = foundStop
                showingStopCodeEntry = false
            }
        }
        .navigationDestination(item: $foundStop) { stop in
            BusArrivalView(stop: stop)
        }
        .refreshable {
            await loadNearbyStops()
        }
        .alert("Open Settings", isPresented: $showingSettingsAlert) {
            Button("Settings") {
                // This would navigate to settings in a real app
                // For now, we'll just show the alert
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please configure your 511.org API key in the Settings tab.")
        }
        .onAppear {
            locationManager.startLocationUpdates()
            Task {
                await loadNearbyStops()
            }
        }
        .onChange(of: locationManager.currentLocation) {
            Task {
                await loadNearbyStops()
            }
        }
        .onChange(of: transitAPI.isAPIKeyConfigured) {
            Task {
                await loadNearbyStops()
            }
        }
        .onChange(of: selectedAgencyRaw) {
            Task {
                await loadNearbyStops()
            }
        }
    }

    @ViewBuilder
    private var filterBanner: some View {
        if let agency = activeAgencyFilter {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundColor(.blue)
                    Text("Showing \(agency.displayName) only")
                        .font(.caption)
                    Spacer()
                    Button(action: { selectedAgencyRaw = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Clear agency filter")
                }
            }
        }
    }

    @ViewBuilder
    private var apiKeyPromptSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                Text("API Key Required")
                    .font(.headline)
                Text("Configure your 511.org API key to get real-time transit data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings") { showingSettingsAlert = true }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            Text("Finding nearby stops...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var locationPromptSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No nearby stops found")
                .font(.headline)
            Text("Make sure location services are enabled")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Enable Location") {
                locationManager.requestLocationPermission()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var stopSections: some View {
        Section(header: Text("Nearby Stops")) {
            ForEach(nearbyStops) { stop in
                NavigationLink(destination: BusArrivalView(stop: stop)) {
                    BusStopRow(
                        stop: stop,
                        currentLocation: locationManager.currentLocation,
                        showAgencyBadge: showAgencyBadges
                    )
                }
            }
        }
    }

    private func loadNearbyStops() async {
        if let location = locationManager.currentLocation {
            nearbyStops = await transitAPI.fetchNearbyStops(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                agencies: queryAgencies
            )
        } else {
            nearbyStops = []
        }

        if let currentLocation = locationManager.currentLocation {
            nearbyStops.sort { stop1, stop2 in
                stop1.distance(to: currentLocation) < stop2.distance(to: currentLocation)
            }
        }

        nearbyStops = favoritesManager.sortStopsWithFavoritesFirst(nearbyStops)
    }
}

struct BusStopRow: View {
    let stop: BusStop
    let currentLocation: CLLocation?
    var showAgencyBadge: Bool = false
    @EnvironmentObject var favoritesManager: FavoritesManager
    @EnvironmentObject var slotsManager: CommuteSlotsManager
    @State private var commutePromptStop: BusStop? = nil
    @State private var commuteEmptySlots: [CommuteSlotsManager.Slot] = []

    private var agencyBadgeText: String? {
        guard showAgencyBadge else { return nil }
        return Agency.named(stop.agency)?.badge ?? stop.agency
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(stop.name)
                            .font(.headline)
                            .lineLimit(1)

                        if stop.isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                    }

                    HStack(spacing: 4) {
                        if let badge = agencyBadgeText {
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.25))
                                .foregroundColor(.secondary)
                                .cornerRadius(3)
                        }
                        Text("Stop \(stop.code)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let currentLocation = currentLocation {
                        let distance = stop.distance(to: currentLocation)
                        Text(formatDistance(distance))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(action: {
                        let isAdding = !favoritesManager.isFavorite(stop.id)
                        favoritesManager.toggleFavorite(stop)
                        if isAdding {
                            let empty = CommuteSlotsManager.Slot.allCases.filter { slotsManager.stopId(for: $0) == nil }
                            if !empty.isEmpty {
                                commuteEmptySlots = empty
                                commutePromptStop = stop
                            }
                        }
                    }) {
                        Image(systemName: stop.isFavorite ? "star.fill" : "star")
                            .foregroundColor(stop.isFavorite ? .yellow : .gray)
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(stop.isFavorite ? "Remove from favorites" : "Add to favorites")
                }
            }
            .confirmationDialog(
                "Add to commute?",
                isPresented: Binding(get: { commutePromptStop != nil }, set: { if !$0 { commutePromptStop = nil } }),
                presenting: commutePromptStop
            ) { pendingStop in
                if commuteEmptySlots.contains(.morning) {
                    Button("Morning Commute") { slotsManager.setStopId(pendingStop.id, for: .morning) }
                }
                if commuteEmptySlots.contains(.afternoon) {
                    Button("Afternoon Commute") { slotsManager.setStopId(pendingStop.id, for: .afternoon) }
                }
                Button("Not Now", role: .cancel) { }
            } message: { pendingStop in
                Text("Use \"\(pendingStop.name)\" as a commute stop?")
            }

            if !stop.routes.isEmpty {
                HStack {
                    ForEach(stop.routes.prefix(3), id: \.self) { route in
                        Text(route)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }

                    if stop.routes.count > 3 {
                        Text("+\(stop.routes.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Tap to view arrivals")
    }

    private var accessibilityDescription: String {
        var parts: [String] = [stop.name]
        if let agency = Agency.named(stop.agency)?.displayName, showAgencyBadge {
            parts.append(agency)
        }
        parts.append("stop code \(stop.code)")
        if let currentLocation = currentLocation {
            parts.append(formatDistance(stop.distance(to: currentLocation)) + " away")
        }
        if stop.isFavorite { parts.append("favorite") }
        if !stop.routes.isEmpty {
            parts.append("routes \(stop.routes.joined(separator: ", "))")
        }
        return parts.joined(separator: ", ")
    }

    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
}

// MARK: - Stop Code Entry

struct StopCodeEntryView: View {
    let transitAPI: TransitAPI
    let agencies: [String]
    let onFound: (BusStop) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [BusStop] = []
    @State private var isSearching = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Find a Stop")
                    .font(.headline)

                TextField("Name or code", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if isSearching {
                    ProgressView()
                } else if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                } else if hasSearched && results.isEmpty {
                    Text("No stops found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !results.isEmpty {
                    Divider()
                    ForEach(results) { stop in
                        Button {
                            onFound(stop)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                HStack(spacing: 4) {
                                    if let agency = Agency.named(stop.agency) {
                                        Text(agency.badge)
                                            .font(.caption2)
                                    }
                                    Text(stop.code)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }

                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.secondary)
                    Button(isSearching ? "Searching…" : "Find") {
                        Task { await search() }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
            }
            .padding()
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        hasSearched = false
        results = []

        if let found = await transitAPI.searchStops(query: trimmed, agencies: agencies) {
            results = found
        } else {
            errorMessage = "Search failed. Check your connection."
        }
        hasSearched = true
        isSearching = false
    }
}

#Preview {
    BusStopListView()
}
