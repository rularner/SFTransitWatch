import SwiftUI
import SFTransitWatchPackage

struct ContentView: View {
    var body: some View {
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
}

#Preview {
    ContentView()
} 