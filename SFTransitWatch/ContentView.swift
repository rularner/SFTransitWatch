import SwiftUI
import SFTransitWatchPackage

struct ContentView: View {
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
    }
}

#Preview {
    ContentView()
        .environmentObject(FavoritesManager())
        .environmentObject(CommuteSlotsManager())
}