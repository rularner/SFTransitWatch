import SwiftUI
import CoreLocation

struct BusStopListView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var transitAPI = TransitAPI()
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var siriManager = SiriManager()
    @State private var nearbyStops: [BusStop] = []
    @State private var isLoading = false
    @State private var showingSettingsAlert = false
    
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
                // Favorites section
                let favoriteStops = favoritesManager.getFavoriteStops(from: nearbyStops)
                if !favoriteStops.isEmpty {
                    Section(header: Text("Favorites")) {
                        ForEach(favoriteStops) { stop in
                            NavigationLink(destination: BusArrivalView(stop: stop)) {
                                BusStopRow(
                                    stop: stop,
                                    currentLocation: locationManager.currentLocation,
                                    favoritesManager: favoritesManager,
                                    siriManager: siriManager
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
                                favoritesManager: favoritesManager,
                                siriManager: siriManager
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Nearby Stops")
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
            siriManager.setupSiriShortcuts()
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
            nearbyStops = []
        }
        
        // Sort by distance if location is available
        if let currentLocation = locationManager.currentLocation {
            nearbyStops.sort { stop1, stop2 in
                stop1.distance(to: currentLocation) < stop2.distance(to: currentLocation)
            }
        }
        
        // Apply favorites sorting
        nearbyStops = favoritesManager.sortStopsWithFavoritesFirst(nearbyStops)
        
        // Donate Siri intent for nearby stops
        siriManager.donateNearbyStopsIntent()
        
        isLoading = false
    }
}

struct BusStopRow: View {
    let stop: BusStop
    let currentLocation: CLLocation?
    let favoritesManager: FavoritesManager
    let siriManager: SiriManager
    
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
                        // Donate Siri intent when user interacts with stops
                        siriManager.donateBusArrivalIntent(stopId: stop.id, stopName: stop.name)
                    }) {
                        Image(systemName: stop.isFavorite ? "star.fill" : "star")
                            .foregroundColor(stop.isFavorite ? .yellow : .gray)
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
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
    }
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
}

#Preview {
    BusStopListView()
} 