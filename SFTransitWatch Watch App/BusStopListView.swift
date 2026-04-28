import SwiftUI
import CoreLocation

struct BusStopListView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var transitAPI = TransitAPI()
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var pinnedStopsManager = PinnedStopsManager()
    @AppStorage(EnabledAgencies.storageKey) private var enabledAgenciesRaw = EnabledAgencies.default
    @State private var nearbyStops: [BusStop] = []
    @State private var showingSettingsAlert = false
    @State private var showingStopCodeEntry = false

    private var enabledAgencies: [String] {
        EnabledAgencies.parse(enabledAgenciesRaw)
    }
    private var showAgencyBadges: Bool {
        enabledAgencies.count > 1
    }

    var body: some View {
        List {
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
                defaultAgency: EnabledAgencies.defaultAgency(enabledAgenciesRaw)
            ) { foundStop in
                pinnedStopsManager.pin(foundStop)
            }
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
        if !pinnedStopsManager.pinned.isEmpty {
            Section(header: Text("Pinned")) {
                ForEach(pinnedStopsManager.pinned) { stop in
                    NavigationLink(destination: BusArrivalView(stop: stop)) {
                        BusStopRow(
                            stop: stop,
                            currentLocation: locationManager.currentLocation,
                            favoritesManager: favoritesManager,
                            showAgencyBadge: showAgencyBadges
                        )
                    }
                }
                .onDelete { pinnedStopsManager.unpin(at: $0) }
            }
        }

        let favoriteStops = favoritesManager.getFavoriteStops(from: nearbyStops)
        if !favoriteStops.isEmpty {
            Section(header: Text("Favorites")) {
                ForEach(favoriteStops) { stop in
                    NavigationLink(destination: BusArrivalView(stop: stop)) {
                        BusStopRow(
                            stop: stop,
                            currentLocation: locationManager.currentLocation,
                            favoritesManager: favoritesManager,
                            showAgencyBadge: showAgencyBadges
                        )
                    }
                }
            }
        }

        Section(header: Text("Nearby Stops")) {
            ForEach(nearbyStops) { stop in
                NavigationLink(destination: BusArrivalView(stop: stop)) {
                    BusStopRow(
                        stop: stop,
                        currentLocation: locationManager.currentLocation,
                        favoritesManager: favoritesManager,
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
                agencies: enabledAgencies
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
    let favoritesManager: FavoritesManager
    var showAgencyBadge: Bool = false

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
                        favoritesManager.toggleFavorite(for: stop.id)
                    }) {
                        Image(systemName: stop.isFavorite ? "star.fill" : "star")
                            .foregroundColor(stop.isFavorite ? .yellow : .gray)
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(stop.isFavorite ? "Remove from favorites" : "Add to favorites")
                }
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
    let defaultAgency: String
    let onFound: (BusStop) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isSearching = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text("Find Stop by Code")
                .font(.headline)

            TextField("Stop code (e.g. 15552)", text: $code)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                Button("Cancel") { dismiss() }
                    .foregroundColor(.secondary)

                Button(isSearching ? "Searching…" : "Find") {
                    Task { await search() }
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
        }
        .padding()
    }

    private func search() async {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil

        if let stop = await transitAPI.fetchStop(code: trimmed, agency: defaultAgency) {
            onFound(stop)
            dismiss()
        } else {
            errorMessage = "Stop \"\(trimmed)\" not found. Check the code and try again."
        }
        isSearching = false
    }
}

#Preview {
    BusStopListView()
}
