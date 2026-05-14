import SwiftUI
import WatchKit
import SFTransitWatchPackage

struct SettingsView: View {
    @StateObject private var transitAPI = TransitAPI()
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var commuteSlotsManager = CommuteSlotsManager()
    @StateObject private var locationManager = LocationManager()
    @State private var apiKey = ""
    @AppStorage("notifications_imminent_arrivals_enabled") private var notificationsEnabled = false
    @AppStorage(EnabledAgencies.storageKey) private var enabledAgenciesRaw = EnabledAgencies.default
    @State private var showingAPIKeyEntry = false
    @State private var nearbyStops: [BusStop] = []

    init(
        favoritesManager: FavoritesManager? = nil,
        commuteSlotsManager: CommuteSlotsManager? = nil
    ) {
        _favoritesManager = StateObject(wrappedValue: favoritesManager ?? FavoritesManager())
        _commuteSlotsManager = StateObject(wrappedValue: commuteSlotsManager ?? CommuteSlotsManager())
    }

    var body: some View {
        List {
            Section(header: Text("API Key")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("511.org API Key")
                        .font(.headline)

                    if apiKey.isEmpty {
                        Text("Not configured")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Text("Configured ✓")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .padding(.vertical, 4)

                Button(apiKey.isEmpty ? "Enter API Key" : "Change API Key") {
                    showingAPIKeyEntry = true
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("To load via email or text:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Send yourself a message containing:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("https://rularner.github.io/sftransitwatch/key?k=YOUR_KEY")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("Then tap the link on your watch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                if !apiKey.isEmpty {
                    Button("Clear API Key") {
                        ConfigurationManager.shared.apiKey = ""
                    }
                    .foregroundColor(.red)
                }
            }

            Section(
                header: Text("Worker proxy"),
                footer: Text("Optional. Send yourself a Messages link of the form https://rularner.github.io/sftransitwatch/wt?u=YOUR_WORKER_URL&t=YOUR_TOKEN and tap it on the watch to set.")
            ) {
                HStack {
                    Text("Worker")
                    Spacer()
                    Text(workerHostDisplay)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if ConfigurationManager.shared.isWorkerConfigured {
                    Button("Clear", role: .destructive) {
                        ConfigurationManager.shared.clearWorkerConfig()
                    }
                }
            }

            Section(header: Text("Agencies")) {
                Text("Pick which Bay Area transit operators to query for nearby stops.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)

                ForEach(Agency.known) { agency in
                    Toggle(isOn: agencyBinding(for: agency)) {
                        VStack(alignment: .leading) {
                            Text(agency.displayName)
                            Text(agency.code)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }

            Section(header: Text("Complication")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Commute Stops")
                        .font(.headline)
                    Text("Shown on your watch face. Morning before noon, afternoon after.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                ForEach(CommuteSlotsManager.Slot.allCases, id: \.self) { slot in
                    NavigationLink {
                        CommuteSlotPickerView(slot: slot, allFavorites: favoriteStopsForPicker, slotsManager: commuteSlotsManager)
                    } label: {
                        HStack {
                            Text(slot.displayName)
                            Spacer()
                            Text(currentStopName(for: slot))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Toggle("Notify me when bus is ≤2 min away", isOn: $notificationsEnabled)
                    .font(.caption)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue {
                            Task {
                                let granted = await BackgroundRefreshController.shared.requestNotificationAuthorization()
                                if !granted { notificationsEnabled = false }
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
                        Text("Tap the star icon next to any stop")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if !favoritesManager.favoriteStopIds.isEmpty {
                    Button("Clear All Favorites") {
                        favoritesManager.clearAllFavorites()
                    }
                    .foregroundColor(.red)
                }
            }

            Section(header: Text("About")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SF Transit Watch")
                        .font(.headline)

                    Text("Version 1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Uses 511.org API for real-time SF Bay Area transit data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            apiKey = ConfigurationManager.shared.apiKey
            locationManager.startLocationUpdates()
            Task {
                if let location = locationManager.currentLocation {
                    nearbyStops = await transitAPI.fetchNearbyStops(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        agencies: EnabledAgencies.parse(enabledAgenciesRaw)
                    )
                }
            }
        }
        .sheet(isPresented: $showingAPIKeyEntry) {
            APIKeyEntryView(apiKey: $apiKey)
        }
    }

    private var workerHostDisplay: String {
        return URL(string: ConfigurationManager.shared.workerBaseURL)?.host ?? ConfigurationManager.shared.workerBaseURL
    }

    private func currentStopName(for slot: CommuteSlotsManager.Slot) -> String {
        guard let id = commuteSlotsManager.stopId(for: slot) else { return "Not set" }
        return nearbyStops.first(where: { $0.id == id })?.name ?? "Stop \(id)"
    }

    private var favoriteStopsForPicker: [BusStop] {
        favoritesManager.getFavoriteStops(from: nearbyStops)
    }

    /// Two-way binding between the per-agency toggle and the comma-separated
    /// `enabled_agencies` string. Disabling the last enabled agency snaps
    /// back to Muni so the app never queries 511 with an empty agency list.
    private func agencyBinding(for agency: Agency) -> Binding<Bool> {
        Binding(
            get: { EnabledAgencies.parse(enabledAgenciesRaw).contains(agency.code) },
            set: { isOn in
                var codes = EnabledAgencies.parse(enabledAgenciesRaw)
                if isOn {
                    if !codes.contains(agency.code) { codes.append(agency.code) }
                } else {
                    codes.removeAll { $0 == agency.code }
                    if codes.isEmpty { codes = [EnabledAgencies.default] }
                }
                enabledAgenciesRaw = EnabledAgencies.format(codes)
            }
        )
    }
}

struct APIKeyEntryView: View {
    @Binding var apiKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("511.org API Key")
                .font(.headline)

            TextField("Paste or dictate key", text: $draftKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onAppear { draftKey = apiKey }

            HStack(spacing: 8) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.secondary)

                Button("Save") {
                    let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    apiKey = trimmed
                    ConfigurationManager.shared.apiKey = trimmed
                    dismiss()
                }
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
