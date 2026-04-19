import SwiftUI
import UIKit

struct SettingsView: View {
    @StateObject private var transitAPI = TransitAPI()
    @StateObject private var favoritesManager = FavoritesManager()
    @State private var apiKey = ""
    @State private var showingAPIKeyAlert = false
    @State private var showingSuccessAlert = false
    @State private var showingClearFavoritesAlert = false
    @AppStorage("511_API_KEY") private var storedAPIKey = ""
    
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
                    
                    Text("Version 1.0")
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
            apiKey = storedAPIKey
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
    
    private func saveAPIKey() {
        guard !apiKey.isEmpty else {
            showingAPIKeyAlert = true
            return
        }
        
        storedAPIKey = apiKey
        transitAPI.setAPIKey(apiKey)
        showingSuccessAlert = true
    }
    
    private func open511Website() {
        if let url = URL(string: "https://511.org/developers/") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
} 