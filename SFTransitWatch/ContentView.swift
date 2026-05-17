import SwiftUI
import SFTransitWatchPackage

struct ContentView: View {
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var slotsManager = CommuteSlotsManager()

    var body: some View {
        NavigationStack {
            BusStopListView()
                .navigationTitle("SF Transit")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
        .environmentObject(favoritesManager)
        .environmentObject(slotsManager)
    }
}

#Preview {
    ContentView()
} 