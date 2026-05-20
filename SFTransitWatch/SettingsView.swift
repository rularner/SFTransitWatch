import SwiftUI
import UIKit
import SFTransitWatchPackage

struct SettingsView: View {
    @StateObject private var transitAPI = TransitAPI()
    @EnvironmentObject var favoritesManager: FavoritesManager
    @EnvironmentObject var slotsManager: CommuteSlotsManager
    @StateObject private var agenciesManager = SharedAgenciesManager()
    @State private var apiKey = ""
    @State private var showingAPIKeyAlert = false
    @State private var showingSuccessAlert = false
    @State private var showingClearFavoritesAlert = false
    @State private var showingMorningPicker = false
    @State private var showingAfternoonPicker = false
    @AppStorage(AlertSettingsManager.alertEnabledKey,
                store: UserDefaults(suiteName: AlertSettingsManager.appGroupSuiteName))
    private var alertsEnabled = true
    @StateObject private var alertSettings = AlertSettingsManager()

    var body: some View {
        List {
            Section(header: Text("511.org API Configuration")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.headline)
                    
                    Text("Get your free API key from 511.org")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        SecureField("Enter your 511.org API key", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Save") {
                            saveAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .disabled(apiKey.isEmpty)
                    }
                }
                .padding(.vertical, 4)
                
                Button("Get API Key") {
                    open511Website()
                }
                .buttonStyle(.bordered)
            }
            
            Section(header: Text("Transit Agencies")) {
                ForEach(Agency.known) { agency in
                    Toggle(isOn: Binding(
                        get: { agenciesManager.isEnabled(agency.code) },
                        set: { _ in agenciesManager.toggle(agency.code) }
                    )) {
                        Text(agency.displayName)
                    }
                }
            }

            Section(
                header: Text("Worker proxy (optional)"),
                footer: Text("Routes API calls through a Cloudflare Worker (yours or a family-shared one) instead of calling 511.org directly. Configure by opening a worker bootstrap link of the form sftransitwatch://wt?u=…&c=…. Leave blank to call 511.org directly with your own API key.")
            ) {
                if ConfigurationManager.shared.isWorkerConfigured {
                    HStack {
                        Text("Worker")
                        Spacer()
                        Text(workerHostDisplay)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Clear", role: .destructive) {
                        ConfigurationManager.shared.clearWorkerConfig()
                    }
                } else {
                    Text("Open a bootstrap link to configure")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !favoritesManager.favoriteStopIds.isEmpty {
                Section(header: Text("Commute Stops")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Morning")
                                .font(.headline)
                            Text(slotDisplayName(for: .morning))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Change") {
                            showingMorningPicker = true
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Afternoon")
                                .font(.headline)
                            Text(slotDisplayName(for: .afternoon))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Change") {
                            showingAfternoonPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .sheet(isPresented: $showingMorningPicker) {
                    CommuteSlotPickerView(
                        slot: .morning,
                        allFavorites: favoriteStopsForPicker,
                        slotsManager: slotsManager
                    )
                }
                .sheet(isPresented: $showingAfternoonPicker) {
                    CommuteSlotPickerView(
                        slot: .afternoon,
                        allFavorites: favoriteStopsForPicker,
                        slotsManager: slotsManager
                    )
                }
            }

            Section(header: Text("Alerts")) {
                Toggle("Notify me of upcoming commute arrivals", isOn: $alertsEnabled)

                if slotsManager.morningStopId != nil || slotsManager.afternoonStopId != nil {
                    ForEach(CommuteSlotsManager.Slot.allCases, id: \.self) { slot in
                        NavigationLink {
                            AlertSlotSettingsView(slot: slot, alertSettings: alertSettings)
                        } label: {
                            HStack {
                                Text(slot.displayName)
                                Spacer()
                                let travel = alertSettings.travelMinutes(for: slot)
                                Text(travel > 0 ? "\(travel) min travel" : "Tap to configure")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section(header: Text("Favorites")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Favorite Stops")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(favoritesManager.favoriteStopIds.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if favoritesManager.favoriteStopIds.isEmpty {
                        Text("No favorite stops yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Tap the star icon next to any stop to add it to favorites")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                
                if !favoritesManager.favoriteStopIds.isEmpty {
                    Button("Clear All Favorites") {
                        showingClearFavoritesAlert = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
            
            Section(header: Text("Siri Integration")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "mic.circle.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Voice Commands")
                                .font(.headline)
                            
                            Text("Use Siri to check bus times hands-free")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        NavigationLink(destination: SiriShortcutsView()) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("About")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SF Transit Watch")
                        .font(.headline)
                    
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Uses 511.org API for real-time transit data in the San Francisco Bay Area.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Data Sources")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• 511.org Transit API")
                    Text("• San Francisco Muni")
                    Text("• BART")
                    Text("• AC Transit")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            apiKey = ConfigurationManager.shared.apiKey
        }
        .alert("API Key Required", isPresented: $showingAPIKeyAlert) {
            Button("OK") { }
        } message: {
            Text("Please enter a valid 511.org API key to get real-time transit data.")
        }
        .alert("API Key Saved", isPresented: $showingSuccessAlert) {
            Button("OK") { }
        } message: {
            Text("Your API key has been saved. The app will now use real-time data from 511.org.")
        }
        .alert("Clear All Favorites", isPresented: $showingClearFavoritesAlert) {
            Button("Clear All", role: .destructive) {
                favoritesManager.clearAllFavorites()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all your favorite stops. This action cannot be undone.")
        }
    }
    
    private var workerHostDisplay: String {
        return URL(string: ConfigurationManager.shared.workerBaseURL)?.host ?? ConfigurationManager.shared.workerBaseURL
    }

    private var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "Unknown"
        }
        return version
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty else {
            showingAPIKeyAlert = true
            return
        }

        ConfigurationManager.shared.apiKey = apiKey
        transitAPI.setAPIKey(apiKey)
        showingSuccessAlert = true
    }
    
    private func open511Website() {
        if let url = URL(string: "https://511.org/developers/") {
            UIApplication.shared.open(url)
        }
    }

    private func slotDisplayName(for slot: CommuteSlotsManager.Slot) -> String {
        guard let stopId = slotsManager.stopId(for: slot) else { return "Not configured" }
        return favoritesManager.favoriteStops.first(where: { $0.id == stopId })?.name ?? "Not configured"
    }

    private var favoriteStopsForPicker: [BusStop] {
        favoritesManager.favoriteStops
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(FavoritesManager())
            .environmentObject(CommuteSlotsManager())
    }
}