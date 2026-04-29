import SwiftUI

struct BusArrivalView: View {
    let stop: BusStop
    @StateObject private var transitAPI = TransitAPI()
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var siriManager = SiriManager()
    @State private var arrivals: [BusArrival] = []
    @State private var lastUpdated = Date()
    
    var body: some View {
        List {
            // Header section
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
                            // Donate Siri intent when user favorites a stop
                            siriManager.donateBusArrivalIntent(stopId: stop.id, stopName: stop.name)
                        }) {
                            Image(systemName: favoritesManager.isFavorite(stop.id) ? "star.fill" : "star")
                                .foregroundColor(favoritesManager.isFavorite(stop.id) ? .yellow : .gray)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if !stop.routes.isEmpty {
                        HStack {
                            ForEach(stop.routes, id: \.self) { route in
                                Text(route)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
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
                } else if arrivals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bus")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                        Text("No upcoming arrivals")
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
                    ForEach(arrivals) { arrival in
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
            siriManager.setupSiriShortcuts()
            // Donate Siri intent when user views arrivals
            siriManager.donateBusArrivalIntent(stopId: stop.id, stopName: stop.name)
            
            // Donate route-specific intents for each route at this stop
            for route in stop.routes {
                siriManager.donateRouteSpecificIntent(route: route)
            }
            
            Task {
                await loadArrivals()
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await loadArrivals()
            }
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

struct BusArrivalRow: View {
    let arrival: BusArrival
    
    var body: some View {
        HStack {
            // Route number
            VStack {
                Text(arrival.route)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(routeColor(for: arrival.route))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.destination)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text(arrival.minutesString)
                        .font(.subheadline)
                        .foregroundColor(arrival.minutesAway <= 5 ? .red : .primary)
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
    }
    
    private func routeColor(for route: String) -> Color {
        // Simple color assignment based on route number
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .teal]
        let index = abs(route.hashValue) % colors.count
        return colors[index]
    }
}

#Preview {
    NavigationView {
        BusArrivalView(stop: BusStop.previewStops[0])
    }
}
