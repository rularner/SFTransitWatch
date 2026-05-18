import SwiftUI
import CoreLocation
import SFTransitWatchPackage

struct BusStopListView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var transitAPI = TransitAPI()
    @EnvironmentObject var favoritesManager: FavoritesManager
    @StateObject private var agenciesManager = SharedAgenciesManager()
    @AppStorage(Agency.selectedAgencyKey) private var selectedAgencyRaw: String = ""
    @State private var nearbyStops: [BusStop] = []
    @State private var showingSettingsAlert = false
    @State private var foundStop: BusStop? = nil
    @State private var showingStopCodeEntry = false

    private var activeAgencyFilter: Agency? {
        guard !selectedAgencyRaw.isEmpty else { return nil }
        return Agency.named(selectedAgencyRaw)
    }

    var body: some View {
        List {
            filterBanner
            AgencyFilterToolbar(agenciesManager: agenciesManager)
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
        .onChange(of: favoritesManager.favoriteStopIds) {
            Task { @MainActor in
                nearbyStops = favoritesManager.sortStopsWithFavoritesFirst(nearbyStops)
            }
        }
        .onChange(of: agenciesManager.enabledCodes) {
            Task { await loadNearbyStops() }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingStopCodeEntry = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Find a stop")
            }
        }
        .sheet(isPresented: $showingStopCodeEntry) {
            StopCodeEntryView(
                transitAPI: transitAPI,
                agencies: agenciesManager.asArray
            ) { stop in
                foundStop = stop
                showingStopCodeEntry = false
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
                Button("Open Settings") {
                    showingSettingsAlert = true
                }
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
                        currentLocation: locationManager.currentLocation
                    )
                }
            }
        }
    }

    @MainActor
    private func loadNearbyStops() async {
        if let location = locationManager.currentLocation {
            let agencies = activeAgencyFilter.map { [$0.code] } ?? agenciesManager.asArray
            nearbyStops = await transitAPI.fetchNearbyStops(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                agencies: agencies
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
    @EnvironmentObject var favoritesManager: FavoritesManager
    @EnvironmentObject var slotsManager: CommuteSlotsManager
    @State private var commutePromptStop: BusStop? = nil
    @State private var commuteEmptySlots: [CommuteSlotsManager.Slot] = []

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

                    Text("Stop \(stop.code)")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

            if let agency = Agency.named(stop.agency) {
                Text(agency.badge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .foregroundColor(.secondary)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
}

struct AgencyFilterToolbar: View {
    @ObservedObject var agenciesManager: SharedAgenciesManager

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Agency.known) { agency in
                        Button(action: { agenciesManager.toggle(agency.code) }) {
                            Text(agency.badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(agenciesManager.isEnabled(agency.code)
                                    ? Color.accentColor
                                    : Color(.systemGray5))
                                .foregroundColor(agenciesManager.isEnabled(agency.code)
                                    ? .white
                                    : .secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(
                            "\(agency.displayName): \(agenciesManager.isEnabled(agency.code) ? "enabled" : "disabled")"
                        )
                        .accessibilityHint("Tap to toggle")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

// MARK: - Stop Search

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
        NavigationStack {
            List {
                Section {
                    TextField("Stop name or code", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                }

                if isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching…")
                            .foregroundColor(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .listRowBackground(Color.clear)
                }

                if hasSearched && !isSearching {
                    if results.isEmpty && errorMessage == nil {
                        Text("No stops found for \"\(query)\"")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .listRowBackground(Color.clear)
                    } else {
                        Section("Results") {
                            ForEach(results) { stop in
                                Button {
                                    onFound(stop)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(stop.name)
                                                .font(.headline)
                                            Text("Stop \(stop.code)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if let agency = Agency.named(stop.agency) {
                                            Text(agency.badge)
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(.systemGray5))
                                                .foregroundColor(.secondary)
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find a Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
            }
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
        .environmentObject(FavoritesManager())
        .environmentObject(CommuteSlotsManager())
}
