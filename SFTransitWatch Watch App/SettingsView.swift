import SwiftUI
import WatchKit

struct SettingsView: View {
    @StateObject private var favoritesManager = FavoritesManager()
    @AppStorage("511_API_KEY") private var storedAPIKey = ""
    @State private var showingAPIKeyEntry = false

    var body: some View {
        List {
            Section(header: Text("API Key")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("511.org API Key")
                        .font(.headline)

                    if storedAPIKey.isEmpty {
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

                Button(storedAPIKey.isEmpty ? "Enter API Key" : "Change API Key") {
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

                if !storedAPIKey.isEmpty {
                    Button("Clear API Key") {
                        storedAPIKey = ""
                    }
                    .foregroundColor(.red)
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
        .sheet(isPresented: $showingAPIKeyEntry) {
            APIKeyEntryView(storedAPIKey: $storedAPIKey)
        }
    }
}

struct APIKeyEntryView: View {
    @Binding var storedAPIKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("511.org API Key")
                .font(.headline)

            TextField("Paste or dictate key", text: $draftKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onAppear { draftKey = storedAPIKey }

            HStack(spacing: 8) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.secondary)

                Button("Save") {
                    storedAPIKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
