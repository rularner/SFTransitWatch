import SwiftUI
import CoreLocation

struct BusStopListView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var transitAPI = TransitAPI()
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var pinnedStopsManager = PinnedStopsManager()
    @State private var nearbyStops: [BusStop] = []
    @State private var isLoading = false
    @State private var showingSettingsAlert = false
    @State private var showingStopCodeEntry = false
    
    var body: some View {
        List {
            if !transitAPI.isAPIKeyConfigured {
                // API Key not configured section
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
            } else if isLoading {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Finding nearby stops...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else if nearbyStops.isEmpty {
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
            } else {
                // Pinned stops (added by code)
                if !pinnedStopsManager.pinned.isEmpty {
                    Section(header: Text("Pinned")) {
                        ForEach(pinnedStopsManager.pinned) { stop in
                            NavigationLink(destination: BusArrivalView(stop: stop)) {
                                BusStopRow(
                                    stop: stop,
                                    currentLocation: locationManager.currentLocation,
                                    favoritesManager: favoritesManager
                                )
                            }
                        }
                        .onDelete { pinnedStopsManager.unpin(at: $0) }
                    }
                }

                // Favorites section
                let favoriteStops = favoritesManager.getFavoriteStops(from: nearbyStops)
                if !favoriteStops.isEmpty {
                    Section(header: Text("Favorites")) {
                        ForEach(favoriteStops) { stop in
                            NavigationLink(destination: BusArrivalView(stop: stop)) {
                                BusStopRow(
                                    stop: stop,
                                    currentLocation: locationManager.currentLocation,
                                    favoritesManager: favoritesManager
                                )
                            }
                        }
                    }
                }

                // All stops section
                Section(header: Text("Nearby Stops")) {
                    ForEach(nearbyStops) { stop in
                        NavigationLink(destination: BusArrivalView(stop: stop)) {
                            BusStopRow(
                                stop: stop,
                                currentLocation: locationManager.currentLocation,
                                favoritesManager: favoritesManager
                            )
                        }
                    }
                }
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
            StopCodeEntryView(transitAPI: transitAPI) { foundStop in
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
    
    private func loadNearbyStops() async {
        isLoading = true
        
        if let location = locationManager.currentLocation {
            nearbyStops = await transitAPI.fetchNearbyStops(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        } else {
            // Fallback to sample data if location not available
            nearbyStops = BusStop.sampleStops
        }
        
        // Sort by distance if location is available
        if let currentLocation = locationManager.currentLocation {
            nearbyStops.sort { stop1, stop2 in
                stop1.distance(to: currentLocation) < stop2.distance(to: currentLocation)
            }
        }
        
        // Apply favorites sorting
        nearbyStops = favoritesManager.sortStopsWithFavoritesFirst(nearbyStops)
        
        isLoading = false
    }
}

struct BusStopRow: View {
    let stop: BusStop
    let currentLocation: CLLocation?
    let favoritesManager: FavoritesManager
    
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
        var parts: [String] = [stop.name, "stop code \(stop.code)"]
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

        if let stop = await transitAPI.fetchStop(code: trimmed) {
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