import SwiftUI
import SFTransitWatchPackage

struct ContentView: View {
    @Binding var deepLinkedStop: BusStop?
    @State private var path: [BusStop] = []

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
                NavigationStack(path: $path) {
                    BusStopListView()
                        .navigationTitle("SF Transit")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink(destination: SettingsView()) {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                        .navigationDestination(for: BusStop.self) { stop in
                            BusArrivalView(stop: stop)
                        }
                }
            }
        }
        .onChange(of: deepLinkedStop) { _, newStop in
            guard let newStop else { return }
            path = [newStop]
            deepLinkedStop = nil
        }
    }
}

#Preview {
    ContentView(deepLinkedStop: .constant(nil))
        .environmentObject(FavoritesManager())
        .environmentObject(CommuteSlotsManager())
}