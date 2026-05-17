import SwiftUI
import SFTransitWatchPackage

struct ContentView: View {
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var slotsManager = CommuteSlotsManager()

    var body: some View {
        Group {
            if SnapshotMode.showArrivalDirectly {
                NavigationStack {
                    BusArrivalView(
                        stop: SnapshotMode.sampleStop,
                        initialTab: SnapshotMode.showLocationTab ? 1 : 0
                    )
                }
            } else {
                NavigationStack {
                    BusStopListView()
                        .navigationTitle("SF Transit")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink(destination: SettingsView()) {
                                    Image(systemName: "gearshape")
                                }
                            }
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